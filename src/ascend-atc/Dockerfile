# syntax=docker/dockerfile:1.7@sha256:a57df69d0ea827fb7266491f2813635de6f17269be881f696fbfdf2d83dda33e

ARG BASE_IMAGE=quay.io/ascend/cann:8.5.0-910b-ubuntu22.04-py3.11@sha256:3faee0835b3900a2a77dbe02775fd34bc521d12e23eb8603f9c9f16013a9d015
FROM ${BASE_IMAGE} AS amct-build

USER root
# Isolate AMCT's Python package versions from the vendor ATC interpreter.
COPY src/ascend-atc/requirements.txt /tmp/amct-requirements.txt
RUN python3.11 -m venv /opt/amct \
    && /opt/amct/bin/python -m pip install --no-cache-dir --only-binary=:all: \
        --requirement /tmp/amct-requirements.txt

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
    && /opt/amct/bin/python -m pip check

FROM ${BASE_IMAGE}

USER root
ENV HOME=/root
LABEL org.opencontainers.image.description="CANN 8.5.0 ATC, AMCT ACL and AMCT ONNX tools for Ascend910B2"

# The vendor image ships the Toolkit and interpreter. Add its offline compiler dependencies.
COPY src/ascend-atc/atc-requirements.txt /tmp/atc-requirements.txt
RUN python3.11 -m pip list --format=freeze > /tmp/atc-constraints.txt \
    && python3.11 -m pip install --no-cache-dir --only-binary=:all: \
        --constraint /tmp/atc-constraints.txt --requirement /tmp/atc-requirements.txt \
    && python3.11 -m pip check \
    && rm /tmp/atc-constraints.txt /tmp/atc-requirements.txt

# Install the matching ACL component into the vendor Toolkit installation.
RUN --mount=type=bind,from=amct-build,source=/tmp/amct_acl,target=/tmp/amct_acl \
    bash /tmp/amct_acl/cann-amct_acl_8.5.0_linux-aarch64.run --quiet --run \
        --install-path=/usr/local/Ascend

COPY --from=amct-build /opt/amct /opt/amct
RUN ln -s /opt/amct/bin/amct_onnx /usr/local/bin/amct_onnx
COPY src/ascend-atc/calibration.cfg /opt/ascend-atc/calibration.cfg

COPY --chmod=0755 vendor/image-kit/scripts/system/finalize-mirror.sh /tmp/finalize-mirror.sh
RUN /tmp/finalize-mirror.sh --mirror upstream && rm /tmp/finalize-mirror.sh

WORKDIR /work
# The vendor entrypoint sets up CANN before executing the supplied command.
CMD ["bash"]
