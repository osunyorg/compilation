# Kelmscott

![Kelmscott Press](kelmscott-press.jpg)

Ce référentiel doit être cloné sur la machine Kelmscott.

## Installation

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/osunyorg/kelmscott.git
cd compilation
bin/setup
bin/start
```

## Mise à jour

```bash
cd compilation
git pull
bin/update
bin/restart
```
