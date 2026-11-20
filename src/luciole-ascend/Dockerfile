# syntax=docker/dockerfile:1.7@sha256:a57df69d0ea827fb7266491f2813635de6f17269be881f696fbfdf2d83dda33e

ARG BASE_IMAGE=ascendai/torch-npu:2.10.0.post7-cann9.2.0-910b-ubuntu22.04-py3.12
FROM ${BASE_IMAGE} AS ascend-dev

ARG DEFAULT_USER=root
ARG DEFAULT_UID=1000
ARG DEFAULT_GID=1000
ARG DEFAULT_GROUPS=""
ARG TZ=Asia/Shanghai
ARG SYSTEM_UPGRADE=false
ARG CMAKE_VERSION=4.3.2
ARG CMAKE_SHA256
ARG DEVSHELL=false
ARG PACKAGE_MIRROR=upstream
ARG SSH_MODE=key-only
ARG WORKSPACE_DIR=/work

LABEL org.opencontainers.image.description="Kunpeng ARM64 and Ascend 910B TorchNPU development and model deployment environment"

COPY --chmod=0755 vendor/image-kit/scripts/system/system.sh /tmp/image-scripts/system.sh
RUN /tmp/image-scripts/system.sh --timezone "${TZ}" --upgrade "${SYSTEM_UPGRADE}"

# Preserve vendor Python packages before apt introduces the distribution interpreter.
COPY --chmod=0755 vendor/image-kit/scripts/python/python-install.sh /tmp/image-scripts/python-install.sh
RUN /tmp/image-scripts/python-install.sh --mode existing

COPY --chmod=0755 vendor/image-kit/assets/ascend-pip-check.sh /usr/local/bin/ascend-pip-check
COPY vendor/image-kit/assets/python-dev-requirements.txt /tmp/image-scripts/python-dev-requirements.txt
COPY src/_assets/ascend-vision-requirements.txt /tmp/image-scripts/ascend-vision-requirements.txt
COPY src/luciole-ascend/python-requirements.txt /tmp/image-scripts/python-requirements.txt
COPY --chmod=0755 vendor/image-kit/scripts/python/ascend-pip-packages.sh /tmp/image-scripts/ascend-pip-packages.sh
RUN /tmp/image-scripts/ascend-pip-packages.sh --requirements /tmp/image-scripts/python-requirements.txt

COPY --chmod=0755 vendor/image-kit/scripts/dev/dev-tools.sh /tmp/image-scripts/dev-tools.sh
RUN /tmp/image-scripts/dev-tools.sh
COPY --chmod=0755 src/_scripts/dev/luciole-dev-tools.sh /tmp/image-scripts/luciole-dev-tools.sh
RUN /tmp/image-scripts/luciole-dev-tools.sh

COPY --chmod=0755 vendor/image-kit/scripts/dev/cmake.sh /tmp/image-scripts/cmake.sh
RUN /tmp/image-scripts/cmake.sh --version "${CMAKE_VERSION}" --sha256 "${CMAKE_SHA256}"

COPY --chmod=0755 vendor/image-kit/scripts/system/user.sh /tmp/image-scripts/user.sh
RUN /tmp/image-scripts/user.sh \
      --username "${DEFAULT_USER}" --uid "${DEFAULT_UID}" --gid "${DEFAULT_GID}" \
      --groups "${DEFAULT_GROUPS}"

COPY --chmod=0755 vendor/image-kit/scripts/system/ssh.sh /tmp/image-scripts/ssh.sh
RUN /tmp/image-scripts/ssh.sh --default-user "${DEFAULT_USER}" --mode "${SSH_MODE}"

COPY --chmod=0755 vendor/image-kit/scripts/system/workspace.sh /tmp/image-scripts/workspace.sh
RUN /tmp/image-scripts/workspace.sh --path "${WORKSPACE_DIR}" --owner "${DEFAULT_USER}"

COPY --chmod=0755 vendor/image-kit/scripts/dev/devshell.sh /tmp/image-scripts/devshell.sh
USER ${DEFAULT_USER}
RUN /tmp/image-scripts/devshell.sh --enabled "${DEVSHELL}"
USER root

FROM ascend-dev AS model-tools-build

USER root
ENV PYTHONPATH=""

ADD --checksum=sha256:ed97befbc0c238f0fffbeecd60d23fdc1e7a0376442a27974eed6d0e61e5a9eb \
    https://ascend-repo.obs.cn-east-2.myhuaweicloud.com/CANN/CANN%209.2.0/Ascend-cann-amct_9.2.0_linux-aarch64.tar.gz /tmp/amct.tar.gz

COPY src/luciole-ascend/amct-requirements.txt /tmp/amct-requirements.txt
COPY src/_assets/ascend-python-dev-requirements.txt /tmp/image-scripts/ascend-python-dev-requirements.txt
RUN --mount=type=cache,target=/tmp/uv-cache,mode=0777 \
    tar -xzf /tmp/amct.tar.gz -C /tmp ./amct_acl ./amct_onnx \
    && uv venv --no-python-downloads --python "$(command -v python3)" /opt/amct \
    && UV_CACHE_DIR=/tmp/uv-cache uv pip install \
        --python /opt/amct/bin/python --link-mode copy --only-binary :all: \
        --requirement /tmp/amct-requirements.txt \
        --requirement /tmp/image-scripts/ascend-python-dev-requirements.txt \
        --requirement /tmp/image-scripts/ascend-vision-requirements.txt \
        /tmp/amct_onnx/amct_onnx-0.24.1-py3-none-linux_aarch64.whl

# Preload the exact ONNX Runtime headers for the offline custom operator build.
ADD --checksum=sha256:1f5b8bcde589106bdf5f0e35dea25f8794bec1288d8aa83d875801b321cdf127 \
    https://cdn.jsdelivr.net/gh/microsoft/onnxruntime@v1.20.0/include/onnxruntime/core/session/onnxruntime_cxx_api.h /tmp/amct_onnx_op/inc/onnxruntime_cxx_api.h
ADD --checksum=sha256:45cb911ad364e61c038e3f01d324b27b15871e0c7cc80435007e4d3f5a70c43a \
    https://cdn.jsdelivr.net/gh/microsoft/onnxruntime@v1.20.0/include/onnxruntime/core/session/onnxruntime_cxx_inline.h /tmp/amct_onnx_op/inc/onnxruntime_cxx_inline.h
ADD --checksum=sha256:573a117ae6b83ead7f53da6cedaa0d7b7d9cdb45c0ba4726bac9081e67696a82 \
    https://cdn.jsdelivr.net/gh/microsoft/onnxruntime@v1.20.0/include/onnxruntime/core/session/onnxruntime_c_api.h /tmp/amct_onnx_op/inc/onnxruntime_c_api.h
ADD --checksum=sha256:a8fb19e4ddaab339e0be13ac21f2644aa517184ffe8c327dd03128bf2a8cbdff \
    https://cdn.jsdelivr.net/gh/microsoft/onnxruntime@v1.20.0/include/onnxruntime/core/session/onnxruntime_session_options_config_keys.h /tmp/amct_onnx_op/inc/onnxruntime_session_options_config_keys.h
ADD --checksum=sha256:6c4db3d1954b266c4febe413351af86cac922e3448538e7e452e51d646e56a4a \
    https://cdn.jsdelivr.net/gh/microsoft/onnxruntime@v1.20.0/include/onnxruntime/core/session/onnxruntime_float16.h /tmp/amct_onnx_op/inc/onnxruntime_float16.h

RUN --network=none tar -xzf /tmp/amct_onnx/amct_onnx_op.tar.gz -C /tmp \
    && cd /tmp/amct_onnx_op \
    && /opt/amct/bin/python setup.py build \
    && uv pip check --python /opt/amct/bin/python \
    && sed -i '1s/$/ -E/' /opt/amct/bin/amct_onnx

COPY src/_assets/onnx-requirements.txt /tmp/image-scripts/onnx-requirements.txt
# Limit parallel compilation when onnxoptimizer builds its ARM64 extension.
RUN --mount=type=cache,target=/tmp/uv-cache,mode=0777 \
    uv venv --no-python-downloads --python "$(command -v python3)" /opt/onnx \
    && UV_CACHE_DIR=/tmp/uv-cache MAX_JOBS=2 uv pip install \
        --python /opt/onnx/bin/python \
        --link-mode copy \
        --requirement /tmp/image-scripts/onnx-requirements.txt \
        --requirement /tmp/image-scripts/ascend-python-dev-requirements.txt \
        --requirement /tmp/image-scripts/ascend-vision-requirements.txt

FROM ascend-dev

RUN --mount=type=bind,from=model-tools-build,source=/tmp/amct_acl,target=/tmp/amct_acl \
    bash /tmp/amct_acl/cann-amct_acl_9.2.0_linux-aarch64.run --quiet --run \
        --install-path=/usr/local/Ascend
COPY --from=model-tools-build /opt/amct /opt/amct
RUN ln -s /opt/amct/bin/amct_onnx /usr/local/bin/amct_onnx
COPY --from=model-tools-build /opt/onnx /opt/onnx

COPY --chmod=0755 vendor/image-kit/scripts/python/ascend-python-packages.sh /tmp/image-scripts/ascend-python-packages.sh
COPY src/luciole-ascend/ais-bench-requirements.txt /tmp/image-scripts/ais-bench-requirements.txt
RUN --mount=type=cache,target=/tmp/pip-cache,mode=0777 \
    PIP_CACHE_DIR=/tmp/pip-cache /tmp/image-scripts/ascend-python-packages.sh \
        --requirements /tmp/image-scripts/ais-bench-requirements.txt

# Configure zsh only after its package has installed the global startup file.
COPY --chmod=0755 vendor/image-kit/scripts/integrations/ascend-environment.sh /tmp/image-scripts/ascend-environment.sh
RUN /tmp/image-scripts/ascend-environment.sh

ARG MICROMAMBA_VERSION=2.10.0-0
ARG MICROMAMBA_SHA256_ARM64=3bb56786e21b9b24024f599fe9185b4a59dc3f9f59937a42311ee583adbbb23c
COPY --chmod=0755 vendor/image-kit/scripts/dev/micromamba.sh /tmp/image-scripts/micromamba.sh
RUN /tmp/image-scripts/micromamba.sh --version "${MICROMAMBA_VERSION}" \
    --sha256-arm64 "${MICROMAMBA_SHA256_ARM64}"

COPY --chmod=0755 vendor/image-kit/scripts/system/finalize-mirror.sh /tmp/image-scripts/finalize-mirror.sh
RUN /tmp/image-scripts/finalize-mirror.sh --mirror "${PACKAGE_MIRROR}" \
    && rm -rf /tmp/image-scripts

COPY --chmod=0755 vendor/image-kit/assets/docker-entrypoint.sh /usr/local/bin/docker-entrypoint
COPY --chmod=0755 vendor/image-kit/assets/ascend-entrypoint.sh /usr/local/bin/ascend-entrypoint

ENV EDITOR=vim \
    DEFAULT_USER=${DEFAULT_USER} \
    HOME=/root \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PACKAGE_MIRROR=${PACKAGE_MIRROR} \
    SSH_MODE=${SSH_MODE} \
    TZ=${TZ} \
    VISUAL=vim \
    PAGER="less -FRX" \
    WORKSPACE_DIR=${WORKSPACE_DIR}

USER ${DEFAULT_USER}
WORKDIR ${WORKSPACE_DIR}
EXPOSE 22
ENTRYPOINT ["/usr/local/bin/ascend-entrypoint"]
CMD ["bash"]
