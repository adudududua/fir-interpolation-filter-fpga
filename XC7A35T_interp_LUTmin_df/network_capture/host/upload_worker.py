#!/usr/bin/env python3
"""Qt worker for an explicitly confirmed or development-mode DACU upload."""
from __future__ import annotations

import socket
import time
from dataclasses import dataclass

try:
    from PySide6.QtCore import QObject, Signal, Slot
except ImportError as exc:
    raise ImportError(
        "upload_worker 需要 PySide6；请安装 requirements-gui.txt"
    ) from exc

from dac24_upload import (
    MSG_ACK,
    UploadPlan,
    UploadProtocolError,
    parse_ack,
)


@dataclass(frozen=True)
class UploadConfig:
    target_address: str = "192.168.1.10"
    target_port: int = 4001
    # GUI 预检后传入实际出站 IPv4；显式绑定可避免上传数据误走 Wi-Fi。
    local_bind_address: str | None = None
    ack_timeout_seconds: float = 0.35
    ack_retries: int = 2
    inter_packet_seconds: float = 0.001


class UploadWorker(QObject):
    """Send one immutable upload plan without blocking the GUI thread."""

    progress = Signal(int, int, str)
    packet_acknowledged = Signal(str, int, int)
    completed = Signal(bool, int, int)
    # confirmed_by_board, sent_datagrams, acknowledged_datagrams
    failed = Signal(str)
    finished = Signal()

    def __init__(self, plan: UploadPlan, config: UploadConfig) -> None:
        super().__init__()
        self.plan = plan
        self.config = config

    @Slot()
    def run(self) -> None:
        sent = 0
        acknowledged = 0
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            if self.config.local_bind_address not in (None, "", "0.0.0.0"):
                sock.bind((self.config.local_bind_address, 0))
            sock.settimeout(self.config.ack_timeout_seconds)
            target = (self.config.target_address, self.config.target_port)
            total_datagrams = len(self.plan.datagrams)
            for index, datagram in enumerate(self.plan.datagrams, start=1):
                confirmed = False
                attempts = self.config.ack_retries + 1 if self.plan.ack_required else 1
                for _attempt in range(attempts):
                    sock.sendto(datagram.data, target)
                    sent += 1
                    if not self.plan.ack_required:
                        break
                    confirmed = self._wait_for_ack(sock, datagram)
                    if confirmed:
                        acknowledged += 1
                        self.packet_acknowledged.emit(
                            datagram.stage,
                            datagram.sequence,
                            datagram.expected_next_offset,
                        )
                        break
                if self.plan.ack_required and not confirmed:
                    raise TimeoutError(
                        f"{datagram.stage} seq={datagram.sequence} 在 "
                        f"{attempts} 次发送后仍未收到匹配 ACK"
                    )
                self.progress.emit(index, total_datagrams, datagram.stage)
                if self.config.inter_packet_seconds > 0.0:
                    time.sleep(self.config.inter_packet_seconds)
            self.completed.emit(self.plan.ack_required, sent, acknowledged)
        except (OSError, TimeoutError, UploadProtocolError) as exc:
            self.failed.emit(str(exc))
        except Exception as exc:
            self.failed.emit(f"上传线程异常：{exc}")
        finally:
            sock.close()
            self.finished.emit()

    def _wait_for_ack(self, sock: socket.socket, datagram) -> bool:
        deadline = time.monotonic() + self.config.ack_timeout_seconds
        while time.monotonic() < deadline:
            sock.settimeout(max(0.001, deadline - time.monotonic()))
            try:
                payload, _peer = sock.recvfrom(2048)
            except socket.timeout:
                return False
            try:
                ack = parse_ack(payload)
            except UploadProtocolError:
                # Unrelated or malformed traffic is not evidence of success.
                continue
            if (
                ack.message_type != MSG_ACK
                or ack.transaction_id != self.plan.transaction_id
                or ack.sequence != datagram.sequence
                or ack.total_samples != self.plan.total_samples
            ):
                continue
            if ack.status_code != 0:
                raise UploadProtocolError(
                    f"板端拒绝 {datagram.stage} seq={datagram.sequence}: "
                    f"{ack.status_name} ({ack.status_code})"
                )
            if ack.next_offset != datagram.expected_next_offset:
                raise UploadProtocolError(
                    f"ACK next_offset={ack.next_offset}，预期 "
                    f"{datagram.expected_next_offset}"
                )
            return True
        return False
