#!/usr/bin/env python3
"""UDP 上传前的轻量网络检查。

这里只使用 Python 标准库：UDP ``connect`` 不会发送数据，但能让操作系统完成
路由选择；随后通过 ``getsockname`` 得到真正会用于发送的本机 IPv4 地址。
"""
from __future__ import annotations

import ipaddress
import socket
from dataclasses import dataclass
from typing import Callable, Optional


class UploadNetworkError(RuntimeError):
    """上传网络配置不安全或无法使用。"""


@dataclass(frozen=True)
class UploadRoute:
    target_address: str
    target_port: int
    local_address: str


def same_ipv4_24(first: str, second: str) -> bool:
    """判断两个 IPv4 地址是否属于相同的 /24 网段。"""

    first_ip = ipaddress.IPv4Address(first)
    second_ip = ipaddress.IPv4Address(second)
    return (int(first_ip) >> 8) == (int(second_ip) >> 8)


def _normalise_ipv4(value: str, label: str) -> str:
    try:
        return str(ipaddress.IPv4Address(value.strip()))
    except (AttributeError, ipaddress.AddressValueError) as exc:
        raise UploadNetworkError(f"{label}不是有效的 IPv4 地址：{value!r}") from exc


def probe_upload_route(
    target_address: str,
    target_port: int,
    local_bind_address: Optional[str] = None,
    *,
    socket_factory: Callable[..., socket.socket] = socket.socket,
) -> UploadRoute:
    """探测发送到 FPGA 时操作系统实际选用的本机 IPv4。

    ``local_bind_address`` 为具体地址时先显式绑定；为空或 ``0.0.0.0`` 时让
    操作系统选择路由。该函数只 connect UDP 套接字，不发送任何数据报。
    """

    target = _normalise_ipv4(target_address, "目标地址")
    if not 1 <= int(target_port) <= 65535:
        raise UploadNetworkError(f"目标 UDP 端口超出范围：{target_port}")

    selected_bind: Optional[str] = None
    if local_bind_address and local_bind_address.strip() not in ("", "0.0.0.0"):
        selected_bind = _normalise_ipv4(local_bind_address, "本机绑定地址")

    sock = socket_factory(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        if selected_bind is not None:
            sock.bind((selected_bind, 0))
        sock.connect((target, int(target_port)))
        local = _normalise_ipv4(str(sock.getsockname()[0]), "当前出站地址")
    except UploadNetworkError:
        raise
    except OSError as exc:
        bind_note = selected_bind or "由 Windows 自动选择"
        raise UploadNetworkError(
            "上传前网络探测失败，尚未发送任何数据报。\n"
            f"本机绑定：{bind_note}\n"
            f"目标 FPGA：{target}:{target_port}\n"
            f"系统错误：{exc}"
        ) from exc
    finally:
        sock.close()

    return UploadRoute(target, int(target_port), local)


def require_direct_fpga_subnet(
    target_address: str,
    target_port: int,
    local_bind_address: Optional[str] = None,
    *,
    socket_factory: Callable[..., socket.socket] = socket.socket,
) -> UploadRoute:
    """探测上传路由，并要求本机与 FPGA 位于相同 /24 网段。"""

    route = probe_upload_route(
        target_address,
        target_port,
        local_bind_address,
        socket_factory=socket_factory,
    )
    if same_ipv4_24(route.local_address, route.target_address):
        return route

    raise UploadNetworkError(
        "上传前网络检查未通过，尚未发送任何数据报。\n\n"
        f"当前出站 IPv4：{route.local_address}\n"
        f"目标 FPGA：{route.target_address}:{route.target_port}\n"
        "两者不在同一 /24 网段，所以 FPGA 无法把 ACK 正确回复给本机。\n\n"
        "请把连接 FPGA 的有线网卡手动设置为：\n"
        "IPv4 地址：192.168.1.20\n"
        "子网掩码：255.255.255.0（/24）\n"
        "默认网关：留空\n\n"
        "设置完成后，在左侧“本机 IPv4”选择 192.168.1.20，"
        "停止并重新开始监听，然后再上传。"
    )
