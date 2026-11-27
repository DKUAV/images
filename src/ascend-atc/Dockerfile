# syntax=docker/dockerfile:1.7@sha256:a57df69d0ea827fb7266491f2813635de6f17269be881f696fbfdf2d83dda33e

ARG BASE_IMAGE=quay.io/ascend/cann:8.5.0-910b-ubuntu22.04-py3.11@sha256:3faee0835b3900a2a77dbe02775fd34bc521d12e23eb8603f9c9f16013a9d015
FROM scratch AS cann-310b-packages
ADD --checksum=sha256:bd702440a2b3bf1e0a07d321ed5cb55c181e954a82d0b8edd4b13039b37ef929 \
    https://ascend-repo.obs.cn-east-2.myhuaweicloud.com/CANN/CANN%208.5.0/Ascend-cann-toolkit_8.5.0_linux-aarch64.run /toolkit.run
ADD --checksum=sha256:16851a5b5bca9057239627db46e1f3bc9a26dfd3e05e5e7f72371c7aac1620bf \
    https://ascend-repo.obs.cn-east-2.myhuaweicloud.com/CANN/CANN%208.5.0/Ascend-cann-310b-ops_8.5.0_linux-aarch64.run /310b-ops.run

FROM ${BASE_IMAGE} AS cann-310b
USER root
# Keep installer metadata changes in this stage and export only the new Toolkit tree.
RUN --network=none --mount=type=bind,from=cann-310b-packages,source=/,target=/tmp/cann-packages \
    mv /etc/Ascend/ascend_cann_install.info /tmp/ascend-cann-910b-install.info \
    && install -d -m 0755 /opt/ascend-310b \
    && env -u PYTHONPATH bash /tmp/cann-packages/toolkit.run --quiet --install --install-for-all \
        --install-path=/opt/ascend-310b \
    && env -u PYTHONPATH bash /tmp/cann-packages/310b-ops.run --quiet --install --install-for-all \
        --install-path=/opt/ascend-310b \
    && test -x /opt/ascend-310b/cann/bin/atc

FROM ${BASE_IMAGE} AS python-requirements

USER root
COPY src/_assets/ascend-python-dev-requirements.txt /tmp/ascend-python-dev-requirements.txt
COPY src/_assets/ascend-vision-requirements.txt /tmp/ascend-vision-requirements.txt

FROM python-requirements AS amct-build

# Isolate AMCT's Python package versions from the vendor ATC interpreter.
ENV PYTHONPATH=""
COPY src/ascend-atc/requirements.txt /tmp/amct-requirements.txt
RUN python3.11 -m venv /opt/amct \
    && /opt/amct/bin/python -m pip install --no-cache-dir --only-binary=:all: \
        --requirement /tmp/amct-requirements.txt \
        --requirement /tmp/ascend-python-dev-requirements.txt \
        --requirement /tmp/ascend-vision-requirements.txt

ADD --checksum=sha256:aa93c0e093214cc3a5172f369d594ea67efb4cee8dcd7eb81416987ee453ab83 \
    https://ascend-repo.obs.cn-east-2.myhuaweicloud.com/CANN/CANN%208.5.0/Ascend-cann-amct_8.5.0_linux-aarch64.tar.gz /tmp/amct.tar.gz

# Supply verified ORT headers so AMCT's setup does not download them itself.
ADD --checksum=sha256:637d059cd1b9c20500c40c9edf6377dedfd74c09ad2497c0fe963cf4fd6033c2 \
    https://cdn.jsdelivr.net/gh/microsoft/onnxruntime@v1.16.0/include/onnxruntime/core/session/onnxruntime_cxx_api.h /tmp/amct_onnx_op/inc/onnxruntime_cxx_api.h
ADD --checksum=sha256:919f6287d4b4bfd96e005d78c6c312cce49f4738b1151cc86b4e532a6f796c97 \
    https://cdn.jsdelivr.net/gh/microsoft/onnxruntime@v1.16.0/include/onnxruntime/core/session/onnxruntime_cxx_inline.h /tmp/amct_onnx_op/inc/onnxruntime_cxx_inline.h
ADD --checksum=sha256:3dec2d05c0fdddc02b131d207c30e8dc0dd9aa8a640f30249d32a52898c687c5 \
    https://cdn.jsdelivr.net/gh/microsoft/onnxruntime@v1.16.0/include/onnxruntime/core/session/onnxruntime_c_api.h /tmp/amct_onnx_op/inc/onnxruntime_c_api.h
ADD --checksum=sha256:a33934b0ce34ecd98faeb99f1b8ddf4a215e9a0801b0e291cb6dcf7c0726e630 \
    https://cdn.jsdelivr.net/gh/microsoft/onnxruntime@v1.16.0/include/onnxruntime/core/session/onnxruntime_session_options_config_keys.h /tmp/amct_onnx_op/inc/onnxruntime_session_options_config_keys.h
ADD --checksum=sha256:ecdcb4a53176c8b3bbcf674788fcf5ec923fb2b5c762c3f6cfb56fdb6c259aa1 \
    https://cdn.jsdelivr.net/gh/microsoft/onnxruntime@v1.16.0/include/onnxruntime/core/session/onnxruntime_float16.h /tmp/amct_onnx_op/inc/onnxruntime_float16.h

RUN --network=none tar -xzf /tmp/amct.tar.gz -C /tmp ./amct_acl ./amct_onnx \
    && /opt/amct/bin/python -m pip install --no-deps /tmp/amct_onnx/amct_onnx-0.23.2-py3-none-linux_aarch64.whl \
    && tar -xzf /tmp/amct_onnx/amct_onnx_op.tar.gz -C /tmp \
    && cd /tmp/amct_onnx_op \
    && /opt/amct/bin/python setup.py build \
    && /opt/amct/bin/python -m pip check \
    && sed -i '1s/$/ -E/' /opt/amct/bin/amct_onnx

FROM python-requirements AS onnx-build

ENV PYTHONPATH=""
COPY src/_assets/onnx-requirements.txt /tmp/onnx-requirements.txt
# Limit parallel compilation when pip builds onnxoptimizer from source.
RUN python3.11 -m venv /opt/onnx \
    && MAX_JOBS=2 /opt/onnx/bin/python -m pip install --no-cache-dir \
        --requirement /tmp/onnx-requirements.txt \
        --requirement /tmp/ascend-python-dev-requirements.txt \
        --requirement /tmp/ascend-vision-requirements.txt

FROM python-requirements

ARG SSH_MODE=key-only
ENV HOME=/root
LABEL org.opencontainers.image.description="CANN 8.5.0 ATC, AMCT, ONNX tools, AIS Bench and developer tools for Ascend910B2 and Ascend310B4"

# Install the compiler, benchmarking and development dependencies in the vendor Python.
COPY src/ascend-atc/atc-requirements.txt /tmp/atc-requirements.txt
RUN <<'BASH'
set -euo pipefail
python3.11 -m pip list --format=freeze > /tmp/atc-constraints.txt
python3.11 -m pip install --no-cache-dir --only-binary=:all: \
    --constraint /tmp/atc-constraints.txt \
    --requirement /tmp/atc-requirements.txt \
    --requirement /tmp/ascend-python-dev-requirements.txt \
    --requirement /tmp/ascend-vision-requirements.txt

# CANN 8.5.0's op-compile-tool lists these standard library modules as distributions.
python3.11 -c 'import getopt, inspect, multiprocessing'
if ! atc_pip_check=$(python3.11 -m pip check); then
    printf '%s\n' "$atc_pip_check"
    test -n "$atc_pip_check"
    if grep -qvE '^op-compile-tool 0\.1\.0 requires (getopt|inspect|multiprocessing), which is not installed\.$' <<<"$atc_pip_check"; then
        exit 1
    fi
fi
rm /tmp/atc-constraints.txt /tmp/atc-requirements.txt \
    /tmp/ascend-python-dev-requirements.txt /tmp/ascend-vision-requirements.txt
BASH

# Install the matching ACL component into the vendor Toolkit installation.
RUN --mount=type=bind,from=amct-build,source=/tmp/amct_acl,target=/tmp/amct_acl \
    bash /tmp/amct_acl/cann-amct_acl_8.5.0_linux-aarch64.run --quiet --run \
        --install-path=/usr/local/Ascend

COPY --from=amct-build /opt/amct /opt/amct
RUN ln -s /opt/amct/bin/amct_onnx /usr/local/bin/amct_onnx
COPY --from=onnx-build /opt/onnx /opt/onnx
COPY --from=cann-310b /opt/ascend-310b /opt/ascend-310b
COPY --chmod=0755 src/ascend-atc/ascend-atc-310b.sh /usr/local/bin/ascend-atc-310b
COPY src/ascend-atc/calibration.cfg /opt/ascend-atc/calibration.cfg

COPY --chmod=0755 vendor/image-kit/scripts/dev/dev-tools.sh /tmp/image-scripts/dev-tools.sh
RUN /tmp/image-scripts/dev-tools.sh

ARG MICROMAMBA_VERSION=2.10.0-0
ARG MICROMAMBA_SHA256_ARM64=3bb56786e21b9b24024f599fe9185b4a59dc3f9f59937a42311ee583adbbb23c
COPY --chmod=0755 vendor/image-kit/scripts/dev/micromamba.sh /tmp/image-scripts/micromamba.sh
RUN /tmp/image-scripts/micromamba.sh --version "${MICROMAMBA_VERSION}" \
    --sha256-arm64 "${MICROMAMBA_SHA256_ARM64}"

COPY --chmod=0755 vendor/image-kit/scripts/dev/devshell.sh /tmp/image-scripts/devshell.sh
RUN /tmp/image-scripts/devshell.sh --enabled true

# Restore CANN in login shells after zsh creates its package-owned startup files.
COPY --chmod=0755 vendor/image-kit/scripts/integrations/ascend-environment.sh /tmp/image-scripts/ascend-environment.sh
RUN /tmp/image-scripts/ascend-environment.sh

COPY --chmod=0755 vendor/image-kit/scripts/system/ssh.sh /tmp/image-scripts/ssh.sh
RUN /tmp/image-scripts/ssh.sh --default-user root --mode "${SSH_MODE}" \
    && rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub

COPY --chmod=0755 vendor/image-kit/scripts/system/finalize-mirror.sh /tmp/image-scripts/finalize-mirror.sh
RUN /tmp/image-scripts/finalize-mirror.sh --mirror upstream && rm -rf /tmp/image-scripts

COPY --chmod=0755 vendor/image-kit/assets/docker-entrypoint.sh /usr/local/bin/docker-entrypoint
COPY --chmod=0755 src/ascend-atc/entrypoint.sh /usr/local/bin/ascend-atc-entrypoint

ENV DEFAULT_USER=root SSH_MODE=${SSH_MODE}
WORKDIR /work
EXPOSE 22
ENTRYPOINT ["/usr/local/bin/ascend-atc-entrypoint"]
CMD ["bash"]
