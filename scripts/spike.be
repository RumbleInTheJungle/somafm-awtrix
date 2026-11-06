# @name     SomaFM Spike
# @desc     Throwaway device test for the SomaFM apps. Results go to the AWTRIX log ([script:SomaFM Spike]).
# @version  0.1
# @ondemand
# @requires somafm_lib
# @config   host text "Clock API address" default="127.0.0.1"
#
# Controls
#   select (release)  play Groove Salad by URL            -> checks sound.play + music.station()
#   left              POST /api/v1/audio/stop to `host`   -> checks loopback HTTP stop
#   right             fetch channels.json (cap 80 KB)     -> checks big download + parser
#   knob turn         radioVolume +/- 5                   -> checks settings.set("radioVolume")
#   knob press        toggle large/small font for line 2  -> legibility check
# Screen: line 1 = music.station() id or "-", line 2 = music.title()
#
# Unofficial hobby project, not affiliated with or endorsed by SomaFM but used
# with their permission. SomaFM's streams and JSON files are not a free data
# feed, and the permission doesn't carry over to forks or other projects. Read
# their terms first: https://somafm.com/contact/tos.html (see also NOTICE.md).

import somafm_lib as sf

class Spike
  var l1, l2, big, host, sel

  def init()
    self.l1 = "spike"
    self.l2 = "press select"
    self.big = true
    self.sel = false
    var h = store.get("host")
    self.host = (h == nil || h == "") ? "127.0.0.1" : h
    log("version " + version() + ", lib has " + str(size(sf.CHANNELS)) + " channels")
    log("split: " + str(sf.split_title("Asonat - Forgotten")))
    log("id: " + str(sf.id_from_station("https://ice2.somafm.com/groovesalad-128-mp3")))
  end

  def loop()
    var st = music.station()
    var id = sf.id_from_station(st)
    self.l1 = id != nil ? id : (st == "" ? "-" : st)
    self.l2 = music.title() != "" ? music.title() : (music.playing() ? "(no title)" : "(not playing)")
  end

  def on_button_event(btn, ev)
    if btn == "select"
      if ev == "press" self.sel = true end
      if ev == "release" && self.sel
        self.sel = false
        var ok = sound.play({"station": sf.stream_url("groovesalad")})
        log("sound.play station -> " + str(ok))
      end
      return true
    end
    if ev != "press" return true end
    if btn == "left"
      var url = "http://" + self.host + "/api/v1/audio/stop"
      http.post(url, "{\"group\":\"radio\"}", def (body, status)
        log("stop via " + url + " -> status " + str(status) + " body " + str(body))
      end, {"headers": {"Content-Type": "application/json"}, "timeout": 5})
    elif btn == "right"
      var t0 = now_ms()
      http.get("https://somafm.com/channels.json", def (body, status)
        if body == nil
          log("channels.json -> nil, status " + str(status))
          return
        end
        var t1 = now_ms()
        var rows = sf.parse_channels(body)
        log("channels.json -> status " + str(status) + ", " + str(size(body)) + " bytes in "
            + str(t1 - t0) + " ms, parsed " + str(size(rows)) + " channels in " + str(now_ms() - t1) + " ms")
        if size(rows) > 0 log("first: " + str(rows[0])) end
      end, {"cap": 81920, "timeout": 15, "headers": {"User-Agent": sf.USER_AGENT}})
    end
    return true
  end

  def on_knob(ev)
    if ev == "left" || ev == "right"
      var v = settings.get("radioVolume")
      log("radioVolume before: " + str(v))
      if v == nil v = 50 end
      v += ev == "left" ? -5 : 5
      log("settings.set radioVolume " + str(v) + " -> " + str(settings.set("radioVolume", v)))
    elif ev == "press"
      self.big = !self.big
    end
    return true
  end

  def draw()
    clear()
    sf.draw_now(self.l1, sf.AMBER, self.l2, sf.WHITE, 0x5CFF39, self.big, {}, {})
  end
end

return Spike()
