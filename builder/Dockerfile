FROM gradle:8.9-jdk17 AS sdk
USER root
RUN apt-get update && apt-get install -y --no-install-recommends curl unzip ca-certificates && rm -rf /var/lib/apt/lists/*
ENV ANDROID_HOME=/opt/android-sdk ANDROID_SDK_ROOT=/opt/android-sdk
RUN mkdir -p ${ANDROID_HOME}/cmdline-tools && \
    curl -fsSL 'https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip' -o /tmp/sdk.zip && \
    unzip -q /tmp/sdk.zip -d /tmp/sdk && mv /tmp/sdk/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest && rm -rf /tmp/sdk*
RUN yes | ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --licenses >/dev/null || true
RUN ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager 'platforms;android-35' 'build-tools;35.0.0'
COPY android/ /src/android/
RUN gradle --no-daemon -p /src/android :xsgpslib:assembleRelease && \
    mkdir -p /out && unzip -p /src/android/xsgpslib/build/outputs/aar/xsgpslib-release.aar classes.jar > /tmp/xsgps.jar && \
    ${ANDROID_HOME}/build-tools/35.0.0/d8 --min-api 26 --lib ${ANDROID_HOME}/platforms/android-35/android.jar --output /out /tmp/xsgps.jar

FROM python:3.12-slim-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends openjdk-17-jre-headless curl ca-certificates && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL 'https://github.com/iBotPeaches/Apktool/releases/download/v3.0.3/apktool_3.0.3.jar' -o /opt/apktool.jar && \
    echo 'dbf930b076c6b9be08d57c449cacefc3bdd6b71ebd59b3066fc0e1f5b14f9423  /opt/apktool.jar' | sha256sum -c -
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 ANDROID_HOME=/opt/android-sdk JOB_ROOT=/tmp/xsgps-builder SIGNING_STORE=/data/signing.jks
COPY --from=sdk /opt/android-sdk/build-tools/35.0.0/ /opt/android-sdk/build-tools/35.0.0/
COPY --from=sdk /out/classes.dex /opt/xsgps/classes.dex
COPY android/xsgpslib/src/main/assets/xsgps_map.html /opt/xsgps/xsgps_map.html
WORKDIR /app
COPY builder/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY builder/server.py builder/cli.py builder/index.html ./
RUN groupadd --system xsgps && useradd --system --gid xsgps xsgps && mkdir -p /data /tmp/xsgps-builder && chown xsgps:xsgps /data /tmp/xsgps-builder
USER xsgps
EXPOSE 8080
CMD ["sh", "-c", "exec uvicorn server:app --host 0.0.0.0 --port ${PORT:-8080} --workers 1"]
