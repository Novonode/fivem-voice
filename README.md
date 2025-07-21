# Rust-Mumble Setup Script

A simple and automated script to install and configure [**Rust-Mumble made by AvarianKnight**](https://github.com/AvarianKnight/rust-mumble), a voice server for FiveM, including dependencies, firewall settings, and system optimizations.

## Features

* Automatically installs necessary dependencies
* Sets up Rust and compiles Rust-Mumble from source
* Optimizes system limits for improved performance
* Generates self-signed certificates if none are present
* Creates and enables a systemd service for management
* Configures firewall settings appropriately
* Automatically launches Rust-Mumble on startup

## Installation & Usage

Run the following command to **automatically install and set up Rust-Mumble**:

```bash
git clone https://github.com/Novonode/Fivem-Voice.git && cd Fivem-Voice && chmod +x novonode-voice-setup.sh && sudo ./novonode-voice-setup.sh
```
