"""Construct real adapters at the application boundary, never inside workflows."""

import shutil

from .privacy import ConnectionInspector, MacRandomiser, PrivacyService, ProfileStore
from .process import Command
from .tor import TorBrowser, TorIpChecker


def create_privacy_service() -> PrivacyService:
    command = Command()
    inspector = ConnectionInspector(command)
    store = ProfileStore()
    return PrivacyService(
        inspector=inspector,
        store=store,
        randomiser=MacRandomiser(command, inspector, store),
        ip_checker=TorIpChecker(command),
        browser=TorBrowser(command, launch=command.detach, which=shutil.which),
    )
