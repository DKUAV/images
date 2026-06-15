#!/bin/bash
# Install .NET SDK 8.0.
# Dev images only.
set -euo pipefail

wget https://dot.net/v1/dotnet-install.sh -O dotnet-install.sh
chmod +x dotnet-install.sh
./dotnet-install.sh --channel 8.0 --install-dir /opt/dotnet
ln -s /opt/dotnet/dotnet /usr/local/bin/dotnet
rm dotnet-install.sh
