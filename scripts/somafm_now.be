# @name     SomaFM Now
# @desc     Channel name, plus artist and title of what the SomaFM radio is playing. Turn the knob to switch favourites, press it to open the tuner. Joins the rotation only while SomaFM plays.
# @author   Thomas
# @version  1.1
# @requires somafm_lib
# @config   big     bool  "Large title"   default=true help="Bigger song title, easier to read from across the room"
# @config   accent  color "Channel name colour" default=#FFA830
# @config   host    text  "Clock API address" default="127.0.0.1" help="Used to open the SomaFM tuner. If it won't open, enter this clock's own IP address."

import somafm_lib as sf

class SomaNow
  var id, raw, st, l1, l2, l2col, eqcol, big, accent, o1, o2
  var favs, favs_src, pending, zap_timer, target, target_ms, old_raw
  var knob_long, host, toast, toast_until, s_tuning

  def init()
    self.id = nil
    self.st = nil
    self.raw = nil
    self.l1 = ""
    self.l2 = ""
    self.l2col = sf.WHITE
    self.eqcol = sf.OFF
    var b = store.get("big")
    self.big = b == nil ? true : b
    var a = store.get("accent")
    self.accent = a == nil ? sf.AMBER : a
    self.o1 = {}
    self.o2 = {"repeat": 1}   # keep the card up until the title has run through once

    var h = store.get("host")
    self.host = (h == nil || h == "") ? "127.0.0.1" : h
    var f = store.get("favs")
    self.favs_src = f == nil ? "" : f
    self.favs = sf.split_csv(self.favs_src)
    self.pending = nil        # favourite chosen with the knob, not tuned yet
    self.zap_timer = nil
    self.target = nil         # favourite being tuned, until its stream takes over
    self.target_ms = 0
    self.old_raw = nil
    self.knob_long = false
    self.toast = ""
    self.toast_until = 0
    self.s_tuning = settings.apply_case("tuning")
  end

  # Which SomaFM channel is playing: recognised from music.station(), or, if
  # that text isn't recognisable, what the SomaFM tuner published for this
  # exact station text.
  def station_id()
    var st = music.station()
    if st != self.st
      self.st = st
      log("station: " + st)
    end
    var id = sf.id_from_station(st)
    if id == nil && st != "" && shared.get("SomaFM.st") == st
      id = shared.get("SomaFM.chan")
    end
    return id
  end

  # Channel name on line 1, "tuning" on line 2. Clearing id and raw makes the
  # next refresh rebuild the lines once the new stream is on.
  def show_tuning(id)
    self.l1 = settings.apply_case(sf.title(id))
    self.l2 = self.s_tuning
    self.l2col = sf.GREY
    self.eqcol = sf.color(id)
    self.id = nil
    self.raw = nil
  end

  # Rebuild the two lines when the station or its stream title changes.
  def refresh()
    var id = self.station_id()
    var raw = music.title()
    if self.pending != nil
      self.show_tuning(self.pending)
      return
    end
    if self.target != nil
      # Done when the new station is on and the old stream's title is gone.
      if (id == self.target && raw != self.old_raw) || now_ms() - self.target_ms > 8000
        self.target = nil
      else
        self.show_tuning(self.target)
        return
      end
    end
    if id == self.id && raw == self.raw return end
    self.id = id
    self.raw = raw
    var c = sf.channel(id)
    var name = c != nil ? c[1] : (id != nil ? id : "")
    var genre = c != nil ? c[2] : ""
    var ln = sf.now_lines(raw, name, genre)
    self.l1 = settings.apply_case(ln[0])
    self.l2 = settings.apply_case(ln[1])
    self.l2col = ln[2] ? sf.WHITE : sf.GREY
    self.eqcol = sf.color(id)
  end

  # The tuner owns the favourites. Keep a copy, because shared values are gone
  # after a reboot until the tuner is opened again.
  def sync_favs()
    var s = shared.get("SomaFM.favs")
    if s != nil && s != self.favs_src
      self.favs_src = s
      self.favs = sf.split_csv(s)
      store.set("favs", s)
    end
  end

  # ---------------------------------------------------------- knob remote

  # Move to the next favourite, but only tune after 600 ms without turning.
  # With no favourites known, the knob keeps its normal function.
  def zap(dir)
    var n = size(self.favs)
    if n == 0 return false end
    var from = self.pending
    if from == nil from = self.target end
    if from == nil from = self.station_id() end
    var i = sf.pos(self.favs, from)
    if i < 0
      i = dir > 0 ? 0 : n - 1
    else
      i = (i + dir + n) % n
    end
    self.pending = self.favs[i]
    self.show_tuning(self.pending)
    if self.zap_timer != nil timer.cancel(self.zap_timer) end
    self.zap_timer = timer.after(600, / -> self.commit_zap())
    return true
  end

  def commit_zap()
    if self.zap_timer != nil
      timer.cancel(self.zap_timer)
      self.zap_timer = nil
    end
    if self.pending == nil return end
    var id = self.pending
    self.pending = nil
    self.target = nil
    if id != self.station_id()
      self.old_raw = music.title()
      if sound.play({"station": sf.stream_url(id)})
        self.target = id
        self.target_ms = now_ms()
      else
        log("sound.play refused " + id)
        self.show_toast("can't play")
      end
    end
    self.refresh()
  end

  def open_tuner()
    self.commit_zap()
    http.put("http://" + self.host + "/api/v1/apps/active", "{\"name\":\"SomaFM\"}",
      def (body, status)
        if status < 200 || status >= 300
          log("opening the tuner failed, status " + str(status) + ". Is it installed as SomaFM? Otherwise set 'Clock API address' to the clock's IP.")
          self.show_toast("open failed")
        end
      end,
      {"headers": {"Content-Type": "application/json"}, "timeout": 5})
  end

  def show_toast(msg)
    self.toast = settings.apply_case(msg)
    self.toast_until = now_ms() + 1500
  end

  def on_knob(ev)
    if ev == "left" || ev == "right"
      return self.zap(ev == "left" ? -1 : 1)
    elif ev == "press"
      self.knob_long = false
    elif ev == "long"
      self.knob_long = true
    elif ev == "release"
      if !self.knob_long self.open_tuner() end
      self.knob_long = false
    end
    return true
  end

  # ---------------------------------------------------------------- hooks

  def should_show()
    if !music.playing() return false end
    self.refresh()
    return self.id != nil || self.pending != nil || self.target != nil
  end

  def on_show()
    self.sync_favs()
    self.refresh()
  end

  def on_hide()
    self.knob_long = false
    self.commit_zap()         # leaving mid-turn still tunes the last choice
  end

  def loop()
    self.sync_favs()
    if music.playing() self.refresh() end
  end

  def draw()
    clear()
    if now_ms() < self.toast_until
      sf.draw_now(self.l1, self.accent, self.toast, self.accent, self.eqcol, self.big, self.o1, self.o2)
    else
      sf.draw_now(self.l1, self.accent, self.l2, self.l2col, self.eqcol, self.big, self.o1, self.o2)
    end
  end
end

return SomaNow()
