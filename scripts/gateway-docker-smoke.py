"""Exercise the actual Compose service without TeamSpeak or third-party Python packages."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import secrets
import socket
import struct
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


class WebSocket:
    """Minimal RFC 6455 client for the gateway's JSON handshake and settings commands."""

    def __init__(self, port, origin):
        self.socket = socket.create_connection(("127.0.0.1", port), timeout=10)
        self.reader = self.socket.makefile("rb")
        key = base64.b64encode(secrets.token_bytes(16)).decode()
        request = (
            f"GET /ws HTTP/1.1\r\nHost: localhost:{port}\r\n"
            "Upgrade: websocket\r\nConnection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n"
            f"Origin: {origin}\r\n\r\n"
        )
        self.socket.sendall(request.encode())
        status = self.reader.readline().decode().strip()
        headers = {}
        while line := self.reader.readline().strip():
            name, value = line.decode().split(":", 1)
            headers[name.lower()] = value.strip()
        self.status = int(status.split()[1])
        if self.status == 101:
            expected = base64.b64encode(hashlib.sha1(
                (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()
            ).digest()).decode()
            assert headers.get("sec-websocket-accept") == expected

    def read(self, count):
        result = self.reader.read(count)
        if len(result) != count:
            raise RuntimeError("Gateway closed the test WebSocket unexpectedly")
        return result

    def send(self, value, opcode=1):
        payload = json.dumps(value).encode() if opcode == 1 else value
        length = len(payload)
        prefix = bytes([0x80 | opcode])
        if length < 126:
            prefix += bytes([0x80 | length])
        elif length < 65536:
            prefix += bytes([0x80 | 126]) + struct.pack("!H", length)
        else:
            prefix += bytes([0x80 | 127]) + struct.pack("!Q", length)
        mask = secrets.token_bytes(4)
        self.socket.sendall(prefix + mask + bytes(
            value ^ mask[index % 4] for index, value in enumerate(payload)
        ))

    def receive(self):
        while True:
            first, second = self.read(2)
            assert first & 0x80 and not second & 0x80
            length = second & 0x7f
            if length == 126:
                length = struct.unpack("!H", self.read(2))[0]
            elif length == 127:
                length = struct.unpack("!Q", self.read(8))[0]
            assert length <= 4 * 1024 * 1024
            payload = self.read(length)
            opcode = first & 0x0f
            if opcode == 9:
                self.send(payload, opcode=10)
            elif opcode == 1:
                return json.loads(payload)
            elif opcode == 8:
                raise RuntimeError("Gateway closed before the expected JSON frame")

    def result(self, command):
        for _ in range(100):
            frame = self.receive()
            if frame.get("kind") == "command_result" and frame.get("command") == command:
                assert frame["outcome"]["status"] == "ok", "Gateway command failed"
                return frame.get("data")
        raise RuntimeError("Gateway did not return the requested command result")

    def close(self):
        self.reader.close()
        self.socket.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", default="nightcord-gateway:local")
    args = parser.parse_args()
    project = "nightcord-smoke-" + secrets.token_hex(6)
    token = secrets.token_hex(24)
    environment = dict(os.environ)
    environment.update({
        "NIGHTCORD_GATEWAY_IMAGE": args.image,
        "NIGHTCORD_GATEWAY_HOST": "127.0.0.1",
        "NIGHTCORD_GATEWAY_PORT": "0",
        "NIGHTCORD_GATEWAY_TOKEN": token,
        "NIGHTCORD_GATEWAY_ORIGINS": "http://localhost:5173,http://127.0.0.1:5173",
        "NIGHTCORD_GATEWAY_PROFILE": "docker-smoke",
    })
    with tempfile.TemporaryDirectory(prefix=project) as directory:
        # Explicit empty env file prevents loading an operator's local .env.
        env_file = Path(directory) / "compose.env"
        env_file.touch(mode=0o600)
        command = ["docker", "compose", "--project-name", project,
                   "--env-file", str(env_file), "--file", str(ROOT / "docker-compose.yaml")]

        def compose(*arguments):
            return subprocess.check_output(command + list(arguments), cwd=ROOT, env=environment, text=True).strip()

        def docker(*arguments):
            return subprocess.check_output(["docker", *arguments], cwd=ROOT, env=environment, text=True).strip()

        def attach(device=None):
            port = int(compose("port", "gateway", "8787").rsplit(":", 1)[1])
            client = WebSocket(port, "http://localhost:5173")
            assert client.status == 101
            assert client.receive()["auth"] == "required"
            client.send({"kind": "auth", "token": token, "device": device})
            welcome = client.receive()
            assert welcome["kind"] == "welcome"
            return client, welcome["device"]

        client = None
        try:
            compose("config", "--quiet")
            compose("up", "--detach", "--no-build", "--pull", "never", "--wait", "--wait-timeout", "90")
            container = compose("ps", "--quiet", "gateway")
            info = json.loads(docker("inspect", container))[0]
            assert info["Config"]["User"] == "10001:10001"
            assert info["HostConfig"]["ReadonlyRootfs"]
            assert info["State"]["Health"]["Status"] == "healthy"
            assert info["Config"]["StopSignal"] == "SIGINT"
            assert all(token not in argument for argument in info["Config"]["Cmd"] or [])
            assert not any(value.split("=", 1)[0].lower() in {"http_proxy", "https_proxy"}
                           for value in info["Config"]["Env"])

            port = int(compose("port", "gateway", "8787").rsplit(":", 1)[1])
            denied = WebSocket(port, "https://untrusted.example")
            assert denied.status == 403
            denied.close()
            rejected = WebSocket(port, "http://127.0.0.1:5173")
            assert rejected.receive()["auth"] == "required"
            rejected.send({"kind": "auth", "token": "invalid-smoke-token"})
            assert rejected.receive()["kind"] == "error"
            rejected.close()

            client, device = attach()
            client.send({"command": "settings"})
            settings = client.result("settings")
            settings["ui"]["language"] = "ja"
            settings["audio"]["activation"]["algorithm"] = "disabled"
            client.send({"command": "settings_update", "payload": settings})
            client.result("settings_update")
            public_id = device.split(".", 1)[0]
            compose("exec", "-T", "gateway", "test", "-s", f"/data/devices/{public_id}/access.key")
            compose("exec", "-T", "gateway", "test", "-s", f"/data/devices/{public_id}/settings.json")
            assert token not in compose("logs", "--no-color", "gateway")
            client.close()
            client = None

            started = time.monotonic()
            compose("stop", "--timeout", "15", "gateway")
            assert time.monotonic() - started < 15, "SIGINT did not shut down promptly"
            state = json.loads(docker("inspect", container))[0]["State"]
            assert state["ExitCode"] == 0 and not state["OOMKilled"]
            compose("up", "--detach", "--no-build", "--pull", "never", "--force-recreate", "--wait", "--wait-timeout", "90")
            assert compose("ps", "--quiet", "gateway") != container
            client, restored_device = attach(device)
            assert restored_device == device
            client.send({"command": "settings"})
            restored = client.result("settings")
            assert restored["ui"]["language"] == "ja"
            assert restored["audio"]["activation"]["algorithm"] == "disabled"
            print("PASS: Compose health, non-root runtime, origin/auth checks, persistent settings and graceful restart.")
        finally:
            if client is not None:
                client.close()
            # The random project owns these containers and volumes exclusively.
            compose("down", "--volumes", "--remove-orphans")


if __name__ == "__main__":
    main()
