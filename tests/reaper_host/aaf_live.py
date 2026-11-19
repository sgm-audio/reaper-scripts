"""Live REAPER 7 + pyaaf2 execution: run INSIDE REAPER's embedded Python.

    reaper -nosplash -cfgfile <cfg>/reaper.ini -newinst -nonewinst tests/reaper_host/aaf_live.py

Authors a real AAF with pyaaf2, parses it with AAFInterface, then builds the project in the
real host with ReaperInterface.build_project and asserts on the resulting REAPER project.
Env: SGM_REPO, SGM_HOST_OUT.  Writes PASS/FAIL lines + HOST_RESULT/HOST_EXIT like the Lua harness.
"""
import os
import sys
import tempfile
import traceback

REPO = os.environ["SGM_REPO"]
OUT = os.environ["SGM_HOST_OUT"]
sys.path.insert(0, REPO)
sys.path.insert(0, os.path.join(REPO, "tests"))

open(OUT, "w").close()
passed = failed = 0


def log(*parts):
    with open(OUT, "a") as fh:
        fh.write(" ".join(str(p) for p in parts) + "\n")


def check(name, fn):
    global passed, failed
    try:
        fn()
        passed += 1
        log("PASS", name)
    except Exception:
        failed += 1
        log("FAIL", name, traceback.format_exc().replace("\n", " | "))


def near(a, b, tol=1e-6, msg=""):
    assert abs(a - b) <= tol, "%s expected %r got %r" % (msg, b, a)


try:
    from reaper_python import *  # noqa: F401,F403  (provided by the REAPER host)
    import reaper_python
    import aaf2  # noqa: F401
    import reaper_ai_integration as rai
    import test_aaf_real as fixture

    # The module expects REAPER to inject RPR_* into its globals; do that explicitly.
    rai.__dict__.update({k: v for k, v in vars(reaper_python).items() if k.startswith("RPR_")})
    rai.have_reaper = True

    log("HOST_VERSION", RPR_GetAppVersion(), "python", sys.version.split()[0])
    tmp = tempfile.mkdtemp(prefix="sgm_aaf_live_")
    fixture.RealAAFRoundTrip.dir = tmp
    fixture.RealAAFRoundTrip.wav_a = os.path.join(tmp, "clipA.wav")
    fixture.RealAAFRoundTrip.pcm_a = fixture.write_sine_wav(fixture.RealAAFRoundTrip.wav_a, 2.0, 440.0)
    fixture.RealAAFRoundTrip.wav_b = os.path.join(tmp, "clipB.wav")
    fixture.RealAAFRoundTrip.pcm_b = fixture.write_sine_wav(fixture.RealAAFRoundTrip.wav_b, 1.0, 880.0)
    aaf_path = os.path.join(tmp, "session.aaf")
    fixture.RealAAFRoundTrip._author(aaf_path)

    iface = rai.AAFInterface()
    assert iface.open(aaf_path)
    out = os.path.join(tmp, "essence")
    os.makedirs(out)
    iface.extract_essence(out, None)
    data = iface.get_composition(0)
    iface.close()

    def clear():
        for i in range(RPR_CountTracks(0) - 1, -1, -1):
            RPR_DeleteTrack(RPR_GetTrack(0, i))

    def build():
        clear()
        rai.ReaperInterface().build_project(data)

    def t_track_and_items():
        build()
        assert RPR_CountTracks(0) == 1, "exactly one track, no scratch 'Insertion' track"
        tr = RPR_GetTrack(0, 0)
        name = RPR_GetSetMediaTrackInfo_String(tr, "P_NAME", "", False)[3]
        assert name == "Gtr DI", name
        assert RPR_CountTrackMediaItems(tr) == 2
        i0, i1 = RPR_GetTrackMediaItem(tr, 0), RPR_GetTrackMediaItem(tr, 1)
        near(RPR_GetMediaItemInfo_Value(i0, "D_POSITION"), 0.0)
        near(RPR_GetMediaItemInfo_Value(i0, "D_LENGTH"), 1.0)
        near(RPR_GetMediaItemInfo_Value(i1, "D_POSITION"), 1.5)
        near(RPR_GetMediaItemInfo_Value(i1, "D_LENGTH"), 0.5)
        near(RPR_GetMediaItemTakeInfo_Value(RPR_GetMediaItemTake(i1, 0), "D_STARTOFFS"), 0.25)

    def t_sources_are_real_audio():
        build()
        tr = RPR_GetTrack(0, 0)
        for idx, rate in ((0, 48000), (1, 48000)):
            take = RPR_GetMediaItemTake(RPR_GetTrackMediaItem(tr, idx), 0)
            src = RPR_GetMediaItemTake_Source(take)
            assert src, "take has a source"
            near(RPR_GetMediaSourceSampleRate(src), rate, 0, "sample rate")
            assert RPR_GetMediaSourceNumChannels(src) == 1

    def t_cursor_preserved():
        clear()
        RPR_SetEditCurPos(3.25, False, False)
        rai.ReaperInterface().build_project(data)
        near(RPR_GetCursorPosition(), 3.25, 1e-9, "edit cursor preserved")

    def t_missing_source_does_not_create_item():
        clear()
        bad = {"tracks": [{"name": "X", "items": [
            {"source": os.path.join(tmp, "nope.wav"), "offset": 0.0, "position": 0.0, "duration": 1.0}]}],
            "markers": []}
        rai.ReaperInterface().build_project(bad)
        assert RPR_CountTracks(0) == 1
        assert RPR_CountTrackMediaItems(RPR_GetTrack(0, 0)) == 0

    def t_undo_removes_whole_import():
        clear()
        RPR_Undo_OnStateChange("fixture")
        rai.ReaperInterface().build_project(data)
        assert RPR_CountTracks(0) == 1
        RPR_Undo_DoUndo2(0)
        assert RPR_CountTracks(0) == 0, "single undo step removes the whole import"

    def t_markers():
        clear()
        d2 = dict(data)
        d2["markers"] = [{"name": "Verse", "position": 2.5, "colour": {"r": 255, "g": 0, "b": 0}}]
        rai.ReaperInterface().build_project(d2)
        found = False
        i = 0
        while True:
            r = RPR_EnumProjectMarkers2(0, i, 0, 0, 0, "", 0)
            if not r[0]:
                break
            if r[5] == "Verse":
                near(r[4], 2.5)
                found = True
            i += 1
        assert found, "marker created in host"

    for n, f in (("aaf.live.track_and_items_exact", t_track_and_items),
                 ("aaf.live.sources_are_real_audio_in_host", t_sources_are_real_audio),
                 ("aaf.live.edit_cursor_preserved", t_cursor_preserved),
                 ("aaf.live.missing_source_creates_no_item", t_missing_source_does_not_create_item),
                 ("aaf.live.single_undo_removes_import", t_undo_removes_whole_import),
                 ("aaf.live.markers_created", t_markers)):
        check(n, f)
except Exception:
    failed += 1
    log("HOST_ERROR", traceback.format_exc().replace("\n", " | "))

log("HOST_RESULT", "pass=%d" % passed, "fail=%d" % failed)
log("HOST_EXIT")
