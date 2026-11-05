# @name     SomaFM
# @desc     SomaFM radio tuner. Pick a channel and it plays on the clock's speaker. Favourites first; knob = volume while playing.
# @author   Thomas
# @version  1.1
# @ondemand
# @requires somafm_lib
# @config   autoclose number "Close after idle"  default=10 min=0 max=120 unit=s help="Return to the clock this many seconds after the last input on the now-playing screen. 0 = never."
# @config   big       bool   "Large title"       default=true help="Bigger song title on the now-playing screen"
# @config   accent    color  "Accent colour"     default=#FFA830
# @config   host      text   "Clock API address" default="127.0.0.1" help="Used by 'Radio off'. If the radio doesn't stop, enter this clock's own IP address."
# @config   online    bool   "Update channel list online" default=true help="Fetch SomaFM's channel list once a day, so seasonal channels come and go"

import somafm_lib as sf

# Timings (ms)
#   list idle close  60000   now-playing idle close: @config autoclose
#   zap settle         600   tune timeout 10000   no-title grace 4000
#   volume overlay    1500   toast 1500

class SomaTuner
  var chans, favs, items, cur, nfav_end, mode
  var l_kind, l_title, l_genre, l_color, l_fav, l_playing
  var tuned, tune_ms, play_failed, pending, zap_timer, last_st, shared_st
  var n_state, n_name, n_genre, n_eqcol, n_raw, n_l1, n_l2, n_l2col
  var vol, vol_until, fav_until, fav_on, toast, toast_until
  var last_input, sel_down, knob_long
  var autoclose, big, accent, host, online
  var s_playing, s_nosignal, s_retrying, s_cantplay, s_radiooff, s_stop, dots
  var o_list, o1, o2

  # ------------------------------------------------------------------ setup

  def cfg(key, dflt)
    var v = store.get(key)
    return v == nil ? dflt : v
  end

  def init()
    self.autoclose = self.cfg("autoclose", 10)
    self.big = self.cfg("big", true)
    self.accent = self.cfg("accent", sf.AMBER)
    self.host = self.cfg("host", "127.0.0.1")
    if self.host == "" self.host = "127.0.0.1" end
    self.online = self.cfg("online", true)

    var f = store.get("favs")
    self.favs = isinstance(f, list) ? f : []

    self.s_playing = settings.apply_case("playing")
    self.s_nosignal = settings.apply_case("no signal")
    self.s_retrying = settings.apply_case("retrying")
    self.s_cantplay = settings.apply_case("can't play")
    self.s_radiooff = settings.apply_case("Radio off")
    self.s_stop = settings.apply_case("stop")
    var t = settings.apply_case("tuning")
    self.dots = [t, t + ".", t + "..", t + "..."]
    self.o_list = {}
    self.o1 = {}
    self.o2 = {}

    self.last_st = nil
    self.shared_st = nil
    self.mode = "list"
    self.items = []
    self.cur = 0
    self.nfav_end = 0
    self.tuned = nil
    self.tune_ms = 0
    self.play_failed = false
    self.pending = nil
    self.zap_timer = nil
    self.n_state = "tuning"
    self.n_name = ""
    self.n_genre = ""
    self.n_eqcol = sf.OFF
    self.n_raw = nil
    self.n_l1 = ""
    self.n_l2 = ""
    self.n_l2col = sf.WHITE
    var v = settings.get("radioVolume")
    self.vol = v == nil ? 50 : v
    self.vol_until = 0
    self.fav_until = 0
    self.fav_on = false
    self.toast = ""
    self.toast_until = 0
    self.last_input = now_ms()
    self.sel_down = false
    self.knob_long = false

    self.load_chans()
    self.build_items()
    # Start on the channel that's playing, else the last one tuned.
    var target = self.playing_id()
    if target == nil target = store.get("last") end
    var i = self.find_item(target)
    if i < 0 i = self.first_channel() end
    self.cur = i
    self.update_list_view()
  end

  def setup()
    self.publish_favs()
    self.maybe_refresh()
  end

  # "SomaFM Now" reads this as SomaFM.favs for its knob remote, and keeps a copy.
  def publish_favs()
    if !shared.set("favs", sf.join_csv(self.favs))
      log("favourites not shared: value refused")
    end
  end

  # ---------------------------------------------------------- channel list

  # Online list from store (refreshed daily) or the built-in table.
  def load_chans()
    var saved = store.get("chans")
    if self.online && isinstance(saved, list) && size(saved) > 0
      var out = []
      for r : saved
        out.push([r[0], r[1], r[2], sf.color(r[0])])
      end
      self.chans = out
      log("channel list: " + str(size(out)) + " from SomaFM, updated " + str(store.get("chans_day")))
    else
      self.chans = sf.CHANNELS
      log("channel list: " + str(size(sf.CHANNELS)) + " built-in")
    end
  end

  # Once a day: fetch channels.json in the background. Failures are silent;
  # the stored or built-in list stays in use.
  def maybe_refresh()
    if !self.online return end
    var y = year()
    if y < 0 return end                                  # clock not set yet
    var today = y * 10000 + month() * 100 + day()
    if store.get("chans_day") == today && store.get("chans") != nil return end
    var cap = 81920
    http.get("https://somafm.com/channels.json", def (body, status)
      if body == nil || status != 200
        log("channel refresh failed: " + str(status))
        return
      end
      if size(body) >= cap
        log("channel refresh: answer truncated, keeping old list")
        return
      end
      var rows = sf.parse_channels(body)
      if size(rows) < 10
        log("channel refresh: only " + str(size(rows)) + " channels parsed, ignored")
        return
      end
      store.set("chans", rows)
      store.set("chans_day", today)
      self.load_chans()
      self.build_items()
      self.update_list_view()
    end, {"cap": cap, "timeout": 15})
  end

  # Channel id of what the radio plays, nil if nothing / not recognisable.
  def playing_id()
    var st = music.station()
    if st != self.last_st
      self.last_st = st
      log("station: " + st)
    end
    return st != "" ? sf.id_from_station(st, self.chans) : nil
  end

  # [title, genre, colour] for any id, also for ids missing from the list.
  def row_of(id)
    var i = sf.index_of(self.chans, id)
    if i >= 0
      var c = self.chans[i]
      return [c[1], c[2], c[3]]
    end
    return [sf.title(id), "off air", sf.color(id)]
  end

  # Visible list: [Radio off] + favourites + everything else, in list order.
  # Items: ["off"] or ["ch", id, title, genre, colour, is_fav]
  def build_items()
    var keep = self.cur_key()
    var items = []
    if music.station() != "" items.push(["off"]) end
    for id : self.favs
      var r = self.row_of(id)
      items.push(["ch", id, r[0], r[1], r[2], true])
    end
    self.nfav_end = size(items)
    for c : self.chans
      if sf.pos(self.favs, c[0]) < 0
        items.push(["ch", c[0], c[1], c[2], c[3], false])
      end
    end
    self.items = items
    var i = self.find_item(keep)
    if i < 0 i = self.first_channel() end
    self.cur = i
  end

  def cur_key()
    if size(self.items) == 0 || self.cur >= size(self.items) return nil end
    var it = self.items[self.cur]
    return it[0] == "off" ? "off" : it[1]
  end

  def find_item(key)
    if key == nil return -1 end
    var i = 0
    while i < size(self.items)
      var it = self.items[i]
      if (key == "off" && it[0] == "off") || (it[0] == "ch" && it[1] == key) return i end
      i += 1
    end
    return -1
  end

  def first_channel()
    var i = 0
    while i < size(self.items)
      if self.items[i][0] == "ch" return i end
      i += 1
    end
    return 0
  end

  def update_list_view()
    if size(self.items) == 0 return end
    var it = self.items[self.cur]
    self.l_kind = it[0]
    if it[0] == "off"
      self.l_title = self.s_radiooff
      self.l_genre = self.s_stop
      self.l_color = sf.GREY
      self.l_fav = false
      self.l_playing = false
    else
      self.l_title = settings.apply_case(it[2])
      self.l_genre = settings.apply_case(it[3])
      self.l_color = it[4]
      self.l_fav = it[5]
      self.l_playing = it[1] == self.playing_id()
    end
  end

  def move(dir)
    var n = size(self.items)
    if n == 0 return end
    self.cur = (self.cur + dir + n) % n
    self.update_list_view()
  end

  def toggle_fav()
    var id = nil
    if self.mode == "now"
      id = self.pending != nil ? self.pending : self.tuned
    elif size(self.items) > 0 && self.items[self.cur][0] == "ch"
      id = self.items[self.cur][1]
    end
    if id == nil return end
    var i = sf.pos(self.favs, id)
    if i < 0
      self.favs.push(id)
      self.fav_on = true
    else
      self.favs.remove(i)
      self.fav_on = false
    end
    store.set("favs", self.favs)
    self.publish_favs()
    self.fav_until = now_ms() + 1000
    self.build_items()
    var j = self.find_item(id)
    if j >= 0 self.cur = j end
    self.update_list_view()
  end

  # ------------------------------------------------------------ playing

  def tune(id)
    self.tuned = id
    self.tune_ms = now_ms()
    self.n_raw = nil
    self.play_failed = !sound.play({"station": sf.stream_url(id)})
    if self.play_failed log("sound.play refused " + id) end
    store.set("last", id)
  end

  def open_now(id)
    self.mode = "now"
    if id != self.playing_id()
      self.tune(id)
    else
      self.tuned = id
      self.tune_ms = 0       # already playing: no tuning phase
      self.n_raw = nil
      self.play_failed = false
    end
    self.update_now()
  end

  def back_to_list()
    self.commit_zap()
    self.mode = "list"
    self.build_items()
    var i = self.find_item(self.tuned)
    if i >= 0 self.cur = i end
    self.update_list_view()
  end

  # Left/right on the now-playing screen: move to the neighbouring channel,
  # but only tune once the user has stopped pressing for 600 ms.
  def zap(dir)
    var n = size(self.items)
    if n == 0 return end
    var i = self.cur
    var guard = 0
    while guard < n
      i = (i + dir + n) % n
      if self.items[i][0] == "ch" break end
      guard += 1
    end
    self.cur = i
    self.pending = self.items[i][1]
    if self.zap_timer != nil timer.cancel(self.zap_timer) end
    self.zap_timer = timer.after(600, / -> self.commit_zap())
    self.update_now()
  end

  def commit_zap()
    if self.zap_timer != nil
      timer.cancel(self.zap_timer)
      self.zap_timer = nil
    end
    if self.pending == nil return end
    var id = self.pending
    self.pending = nil
    if id != self.playing_id() self.tune(id) end
    self.update_now()
  end

  # Work out what the now-playing screen shows. Called from loop() (1 Hz)
  # and after every input that changes the channel.
  def update_now()
    var id = self.pending != nil ? self.pending : self.tuned
    var r = self.row_of(id)
    self.n_name = settings.apply_case(r[0])
    self.n_genre = settings.apply_case(r[1])
    self.n_eqcol = r[2]
    if self.pending != nil
      self.n_state = "tuning"
      return
    end
    if self.play_failed
      self.n_state = "error"
      return
    end
    var since = now_ms() - self.tune_ms
    var pid = self.playing_id()
    # Playing "our" channel = the radio plays and the station is either
    # recognised as the tuned channel or not recognisable at all. A different
    # known channel means the previous stream is still on (we're tuning).
    if music.playing() && (pid == self.tuned || pid == nil)
      var raw = music.title()
      if raw == "" && self.tune_ms != 0 && since < 4000
        self.n_state = "tuning"                 # give the stream a moment to send a title
        return
      end
      self.n_state = "play"
      self.publish()
      if raw != self.n_raw
        self.n_raw = raw
        var ln = sf.now_lines(raw, r[0], r[1])
        self.n_l1 = settings.apply_case(ln[0])
        self.n_l2 = settings.apply_case(ln[1])
        self.n_l2col = ln[2] ? sf.WHITE : sf.GREY
      end
    elif self.tune_ms != 0 && since < 10000
      self.n_state = "tuning"
    else
      self.n_state = "nosignal"                 # AWTRIX keeps retrying by itself
    end
  end

  # Tell "SomaFM Now" which channel belongs to the current station text, in
  # case it can't recognise the text itself (read as SomaFM.chan / SomaFM.st).
  def publish()
    var st = music.station()
    if st == self.shared_st return end
    self.shared_st = st
    shared.set("chan", self.tuned)
    shared.set("st", st)
  end

  def change_volume(delta)
    var v = settings.get("radioVolume")
    if v == nil v = self.vol end
    v += delta
    if v < 0 v = 0 end
    if v > 100 v = 100 end
    if !settings.set("radioVolume", v) log("radioVolume not accepted") end
    self.vol = v
    self.vol_until = now_ms() + 1500
  end

  def radio_off()
    self.show_toast("stopping")
    http.post("http://" + self.host + "/api/v1/audio/stop", "{\"group\":\"radio\"}",
      def (body, status)
        if status >= 200 && status < 300
          self.show_toast("radio off")
        else
          self.show_toast("off failed")
          log("radio off failed, status " + str(status) + ". Set 'Clock API address' to the clock's IP.")
        end
        self.build_items()
        self.update_list_view()
      end,
      {"headers": {"Content-Type": "application/json"}, "timeout": 5})
  end

  def show_toast(msg)
    self.toast = settings.apply_case(msg)
    self.toast_until = now_ms() + 1500
  end

  # --------------------------------------------------------------- input

  def touch()
    self.last_input = now_ms()
  end

  # Select / knob press: open the highlighted channel, or go back to the list.
  def activate()
    if self.mode == "list"
      if size(self.items) == 0 return end
      var it = self.items[self.cur]
      if it[0] == "off"
        self.radio_off()
      else
        self.open_now(it[1])
      end
    else
      self.back_to_list()
    end
  end

  def on_button_event(btn, ev)
    self.touch()
    if btn == "select"
      # Act on release: a held select never releases to us, it exits the app.
      if ev == "press"
        self.sel_down = true
      elif ev == "release" && self.sel_down
        self.sel_down = false
        self.activate()
      end
      return true
    end
    if btn == "left" || btn == "right"
      var dir = btn == "left" ? -1 : 1
      if self.mode == "list"
        if ev == "press" || ev == "repeat" self.move(dir) end
      elif ev == "press"
        self.zap(dir)
      end
      return true
    end
    return false
  end

  def on_knob(ev)
    self.touch()
    if ev == "left" || ev == "right"
      var dir = ev == "left" ? -1 : 1
      if self.mode == "list"
        self.move(dir)
      else
        self.change_volume(dir * 5)
      end
    elif ev == "press"
      self.knob_long = false
    elif ev == "long"
      self.knob_long = true
      self.toggle_fav()
    elif ev == "release"
      if !self.knob_long self.activate() end
      self.knob_long = false
    end
    return true
  end

  def on_hide()
    self.sel_down = false
    self.knob_long = false
    self.commit_zap()            # leaving mid-zap still tunes the last choice
  end

  # ---------------------------------------------------------------- loop

  def loop()
    var idle = now_ms() - self.last_input
    if self.mode == "now"
      self.update_now()
      if self.autoclose > 0 && self.n_state == "play" && idle > self.autoclose * 1000
        rotation.close()
      elif idle > 60000
        rotation.close()            # never get stuck on "tuning" / "no signal"
      end
    else
      # keep "Radio off" and the playing marker in step with the radio
      var has_off = size(self.items) > 0 && self.items[0][0] == "off"
      if has_off != (music.station() != "") self.build_items() end
      self.update_list_view()
      if idle > 60000 rotation.close() end
    end
  end

  # ---------------------------------------------------------------- draw

  def draw()
    clear()
    if self.mode == "list"
      self.draw_list()
    else
      self.draw_now_mode()
    end
  end

  def draw_list()
    var w = width()
    rect_fill(0, 0, 2, 15, self.l_color)
    font("small")
    scroll_text(4, 6, w - 4, self.l_title, sf.WHITE, self.o_list)
    if now_ms() < self.toast_until
      text(4, 14, self.toast, self.accent)
    elif self.l_kind == "off"
      rect_fill(4, 9, 5, 5, self.accent)
      text(11, 14, self.l_genre, sf.GREY)
    elif self.l_playing
      sf.draw_eq(4, 9, 5, self.l_color)
      text(10, 14, self.s_playing, self.accent)
    elif self.l_fav
      sf.draw_star(4, 9, self.accent)
      text(10, 14, self.l_genre, sf.GREY)
    else
      text(4, 14, self.l_genre, sf.GREY)
    end
    # position bar: dim track, gap after the favourites, 3 px cursor
    var n = size(self.items)
    rect_fill(0, 15, w, 1, sf.TRACK)
    if n > 1
      if self.nfav_end > 0 && self.nfav_end < n
        pixel(self.nfav_end * (w - 3) / (n - 1) + 1, 15, 0x000000)
      end
      rect_fill(self.cur * (w - 3) / (n - 1), 15, 3, 1, self.accent)
    end
  end

  def draw_now_mode()
    var w = width()
    if self.n_state == "play"
      sf.draw_now(self.n_l1, self.accent, self.n_l2, self.n_l2col, self.n_eqcol, self.big, self.o1, self.o2)
    else
      rect_fill(0, 0, 2, 15, self.n_eqcol)
      font("small")
      if self.n_state == "tuning"
        scroll_text(4, 6, w - 4, self.n_name, self.n_eqcol, self.o_list)
        text(4, 14, self.dots[(now_ms() / 400) % 4], sf.GREY)
      elif self.n_state == "nosignal"
        text(4, 6, self.s_nosignal, self.accent)
        text(4, 14, self.s_retrying, sf.GREY)
      else
        text(4, 6, self.s_cantplay, self.accent)
        text(4, 14, self.n_name, sf.GREY)
      end
    end
    var now = now_ms()
    if now < self.fav_until
      sf.draw_star(w - 5, 0, self.fav_on ? self.accent : sf.GREY)
    end
    if now < self.vol_until
      rect_fill(0, 15, w, 1, sf.TRACK)
      rect_fill(0, 15, self.vol * w / 100, 1, sf.TEAL)
    end
  end
end

return SomaTuner()
