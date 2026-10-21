- install zellij
- install pi — needs node 22 first (Ubuntu 24.04 ships 18):

  ```sh
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
  npm install -g @earendil-works/pi-coding-agent   # -> /usr/bin/pi, config at ~/.pi
  ```
