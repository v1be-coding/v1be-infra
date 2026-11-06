# Claude's working environment. It holds no admin login (ADR-0012).
# Every download is pinned and checked. To update a tool, change its version and
# hash together. The AWS CLI publishes no hash, so hash the zip yourself.
FROM debian@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4

ARG TERRAFORM_VERSION=1.17.1
ARG TERRAFORM_SHA256=4638628058e71a55212b1c563712eac03b902128f40740f3dc8174df12135061
ARG TFLINT_VERSION=0.65.0
ARG TFLINT_SHA256=d4c545ed2e29d6338604b586f34f544f380f70f243aa72f7b484713835eaec61
ARG AWS_VERSION=2.39.4
ARG AWS_SHA256=5153610ddd5dff13d43b2965c92d58f16e9f3f54164eea76d3abb29f38787597
ARG GH_VERSION=2.103.3
ARG GH_SHA256=4c806978ffce1cec70853302a56d70ac6da4f19bae7adca4e1a8ab00633dd91d
ARG NODE_VERSION=24.22.2
ARG NODE_SHA256=48cc0e21e048790e54c0cf5749c2725005313d652651c40b7a21feb9697aaf75
ARG CLAUDE_CODE_VERSION=2.1.318

# The second group is what Playwright lists for Chromium on Debian 13. Each repo
# pins its own Playwright and downloads its own browser.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash ca-certificates curl git jq less procps ripgrep shellcheck unzip xz-utils \
      fonts-liberation libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 \
      libatspi2.0-0t64 libcairo2 libcups2t64 libdbus-1-3 libdrm2 libgbm1 \
      libglib2.0-0t64 libnspr4 libnss3 libpango-1.0-0 libx11-6 libxcb1 \
      libxcomposite1 libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/tools

RUN curl -fsSL -o terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
 && echo "${TERRAFORM_SHA256}  terraform.zip" | sha256sum -c - \
 && unzip -q terraform.zip terraform -d /usr/local/bin

RUN curl -fsSL -o tflint.zip "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_amd64.zip" \
 && echo "${TFLINT_SHA256}  tflint.zip" | sha256sum -c - \
 && unzip -q tflint.zip tflint -d /usr/local/bin

RUN curl -fsSL -o aws.zip "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWS_VERSION}.zip" \
 && echo "${AWS_SHA256}  aws.zip" | sha256sum -c - \
 && unzip -q aws.zip \
 && ./aws/install

RUN curl -fsSL -o gh.tar.gz "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
 && echo "${GH_SHA256}  gh.tar.gz" | sha256sum -c - \
 && tar -xzf gh.tar.gz --strip-components=2 -C /usr/local/bin "gh_${GH_VERSION}_linux_amd64/bin/gh"

RUN curl -fsSL -o node.tar.xz "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
 && echo "${NODE_SHA256}  node.tar.xz" | sha256sum -c - \
 && tar -xJf node.tar.xz --strip-components=1 -C /usr/local --exclude=CHANGELOG.md --exclude=LICENSE --exclude=README.md

WORKDIR /
RUN rm -rf /tmp/tools

RUN useradd --create-home --uid 1000 --shell /bin/bash dev \
 && mkdir -p /home/dev/.aws /home/dev/.claude-config /home/dev/.config/gh /workspaces/v1be/episodes \
 && chown -R dev:dev /home/dev/.aws /home/dev/.claude-config /home/dev/.config /workspaces/v1be/episodes \
 && git config --system safe.directory /workspaces/v1be/v1be-infra \
 && git config --system user.name v1be-bot \
 && git config --system user.email 352911507+v1be-bot@users.noreply.github.com \
 && git config --system credential.https://github.com.helper '!gh auth git-credential'

ENV GIT_TERMINAL_PROMPT=0 \
    GCM_INTERACTIVE=never \
    CLAUDE_CONFIG_DIR=/home/dev/.claude-config \
    DISABLE_AUTOUPDATER=1 \
    PATH=/home/dev/.local/bin:$PATH

USER dev
RUN curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_CODE_VERSION}"
