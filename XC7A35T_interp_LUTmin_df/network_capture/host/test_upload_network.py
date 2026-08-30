#!/usr/bin/env python3
"""上传网卡选择与 /24 预检的回归测试。"""
from __future__ import annotations

import unittest

from upload_network import (
    UploadNetworkError,
    probe_upload_route,
    require_direct_fpga_subnet,
    same_ipv4_24,
)


class FakeDatagramSocket:
    def __init__(self, selected_local: str) -> None:
        self.selected_local = selected_local
        self.bound = None
        self.connected = None
        self.closed = False

    def bind(self, address) -> None:
        self.bound = address
        self.selected_local = address[0]

    def connect(self, address) -> None:
        self.connected = address

    def getsockname(self):
        return self.selected_local, 49152

    def close(self) -> None:
        self.closed = True


class UploadNetworkTests(unittest.TestCase):
    def test_same_ipv4_24(self) -> None:
        self.assertTrue(same_ipv4_24("192.168.1.20", "192.168.1.10"))
        self.assertFalse(same_ipv4_24("169.254.18.213", "192.168.1.10"))

    def test_route_probe_uses_explicit_selected_address(self) -> None:
        fake = FakeDatagramSocket("10.0.0.5")
        route = probe_upload_route(
            "192.168.1.10",
            4001,
            "192.168.1.20",
            socket_factory=lambda *_args: fake,
        )
        self.assertEqual(fake.bound, ("192.168.1.20", 0))
        self.assertEqual(fake.connected, ("192.168.1.10", 4001))
        self.assertEqual(route.local_address, "192.168.1.20")
        self.assertTrue(fake.closed)

    def test_wildcard_uses_operating_system_route(self) -> None:
        fake = FakeDatagramSocket("192.168.1.20")
        route = require_direct_fpga_subnet(
            "192.168.1.10",
            4001,
            "0.0.0.0",
            socket_factory=lambda *_args: fake,
        )
        self.assertIsNone(fake.bound)
        self.assertEqual(route.local_address, "192.168.1.20")

    def test_link_local_address_is_blocked_with_actionable_chinese_message(self) -> None:
        fake = FakeDatagramSocket("169.254.18.213")
        with self.assertRaises(UploadNetworkError) as raised:
            require_direct_fpga_subnet(
                "192.168.1.10",
                4001,
                socket_factory=lambda *_args: fake,
            )
        message = str(raised.exception)
        for expected in (
            "尚未发送任何数据报",
            "当前出站 IPv4：169.254.18.213",
            "目标 FPGA：192.168.1.10:4001",
            "192.168.1.20",
            "255.255.255.0",
        ):
            self.assertIn(expected, message)


if __name__ == "__main__":
    unittest.main(verbosity=2)
