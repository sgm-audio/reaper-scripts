"""Regression: ReaperInterface.build_project must roll back on failure."""

import os
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import reaper_ai_integration as rai  # noqa: E402


class FakeReaper:
    def __init__(self, fail_on_track=None):
        self.tracks = [{"name": "existing"}]
        self.undo = 0
        self.refresh = 0
        self.fail_on_track = fail_on_track

    def installed(self):
        return patch.dict(rai.__dict__, {
            "RPR_GetCursorPosition": lambda: 0.0,
            "RPR_Undo_BeginBlock": lambda: setattr(self, "undo", self.undo + 1),
            "RPR_Undo_EndBlock": lambda *_: setattr(self, "undo", self.undo - 1),
            "RPR_PreventUIRefresh": lambda d: setattr(self, "refresh", self.refresh + d),
            "RPR_GetNumTracks": lambda: len(self.tracks),
            "RPR_InsertTrackAtIndex": lambda i, _w: self.tracks.insert(i, {"name": "new"}),
            "RPR_GetTrack": lambda _p, i: self.tracks[i] if i < len(self.tracks) else None,
            "RPR_GetSetMediaTrackInfo_String": self._name,
            "RPR_DeleteTrack": lambda t: self.tracks.remove(t),
            "RPR_SetEditCurPos": lambda *_: None,
            "RPR_UpdateArrange": lambda: None,
            "RPR_SetMediaTrackInfo_Value": lambda *_: None,
        })

    def _name(self, track, _key, name, _set):
        if name == self.fail_on_track:
            raise RuntimeError("boom")
        track["name"] = name


class AafRollbackTests(unittest.TestCase):
    @staticmethod
    def names(fake):
        return [t["name"] for t in fake.tracks]

    def test_failure_removes_created_tracks_and_balances_state(self):
        fake = FakeReaper(fail_on_track="Track B")
        data = {"tracks": [{"name": "Track A"}, {"name": "Track B"}], "markers": []}
        with fake.installed(), self.assertRaises(RuntimeError):
            rai.ReaperInterface().build_project(data)
        self.assertEqual(self.names(fake), ["existing"])
        self.assertEqual(fake.undo, 0)
        self.assertEqual(fake.refresh, 0)

    def test_success_keeps_tracks_without_scratch_insertion_track(self):
        fake = FakeReaper()
        data = {"tracks": [{"name": "Track A"}], "markers": []}
        with fake.installed():
            rai.ReaperInterface().build_project(data)
        self.assertEqual(self.names(fake), ["existing", "Track A"])
        self.assertEqual((fake.undo, fake.refresh), (0, 0))


if __name__ == "__main__":
    unittest.main()
