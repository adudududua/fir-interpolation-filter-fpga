#!/usr/bin/env python3
"""Regression tests for worker-to-GUI signal thread affinity."""
from __future__ import annotations

import os
import time
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import QObject, QThread, Signal, Slot
from PySide6.QtWidgets import QApplication

from gui_app import MainWindow


class _AckBurst(QObject):
    acknowledged = Signal(str, int, int)
    finished = Signal()

    @Slot()
    def run(self) -> None:
        for sequence in range(256):
            self.acknowledged.emit("WAVE", sequence, (sequence + 1) * 256)
        self.finished.emit()


class GuiThreadSafetyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = QApplication.instance() or QApplication([])

    def test_worker_ack_burst_is_handled_only_on_gui_thread(self) -> None:
        window = MainWindow()
        handled_on_gui_thread: list[bool] = []

        def record_log(_level: str, _message: str) -> None:
            handled_on_gui_thread.append(
                QThread.currentThread() == self.app.thread()
            )

        window._append_log = record_log  # type: ignore[method-assign]
        thread = QThread()
        emitter = _AckBurst()
        emitter.moveToThread(thread)
        thread.started.connect(emitter.run)
        emitter.acknowledged.connect(window._on_upload_packet_acknowledged)
        emitter.finished.connect(thread.quit)
        thread.start()

        deadline = time.monotonic() + 5.0
        while thread.isRunning() and time.monotonic() < deadline:
            self.app.processEvents()
        thread.wait(1000)
        self.app.processEvents()

        self.assertFalse(thread.isRunning())
        self.assertEqual(len(handled_on_gui_thread), 256)
        self.assertTrue(all(handled_on_gui_thread))
        window.deleteLater()
        thread.deleteLater()
        self.app.processEvents()


if __name__ == "__main__":
    unittest.main(verbosity=2)
