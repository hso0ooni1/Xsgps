# Railway Docker image for the authorized XsGPS Debug APK/XAPK builder.
FROM gradle:8.9-jdk17 AS sdk
USER root
RUN apt-get update && apt-get install -y --no-install-recommends curl unzip ca-certificates && rm -rf /var/lib/apt/lists/*
ENV ANDROID_HOME=/opt/android-sdk ANDROID_SDK_ROOT=/opt/android-sdk
RUN mkdir -p ${ANDROID_HOME}/cmdline-tools/latest && \
    curl -fsSL 'https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip' -o /tmp/androidcmd.zip && \
    unzip -q /tmp/androidcmd.zip -d /tmp/cmdline && \
    mv /tmp/cmdline/cmdline-tools/* ${ANDROID_HOME}/cmdline-tools/latest/ && \
    rm -rf /tmp/androidcmd.zip /tmp/cmdline && \
    yes | ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --sdk_root=${ANDROID_HOME} --licenses >/dev/null || true
RUN ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --sdk_root=${ANDROID_HOME} 'platforms;android-35' 'build-tools;35.0.0'
COPY android/ /src/android/
RUN sed -i "/id 'com.android.application' version/a\    id 'com.android.library' version '8.7.3' apply false" /src/android/build.gradle && \
    gradle --no-daemon -p /src/android :xsgpslib:assembleRelease && \
    mkdir -p /out && \
    unzip -p /src/android/xsgpslib/build/outputs/aar/xsgpslib-release.aar classes.jar > /tmp/xsgps-classes.jar && \
    ${ANDROID_HOME}/build-tools/35.0.0/d8 --min-api 26 --lib ${ANDROID_HOME}/platforms/android-35/android.jar \
        --output /out /tmp/xsgps-classes.jar

FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends openjdk-17-jre-headless curl unzip zip ca-certificates && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL 'https://github.com/iBotPeaches/Apktool/releases/download/v3.0.3/apktool_3.0.3.jar' -o /opt/apktool.jar && \
    echo 'dbf930b076c6b9be08d57c449cacefc3bdd6b71ebd59b3066fc0e1f5b14f9423  /opt/apktool.jar' | sha256sum -c -
COPY --from=sdk /opt/android-sdk/build-tools/35.0.0/ /opt/android/build-tools/35.0.0/
COPY --from=sdk /out/classes.dex /opt/xsgps/classes.dex
COPY --from=sdk /src/android/xsgpslib/src/main/assets/xsgps_map.html /opt/xsgps/xsgps_map.html
WORKDIR /app
COPY builder/source.part* /tmp/sourceparts/
RUN cat /tmp/sourceparts/source.part1 /tmp/sourceparts/source.part2 /tmp/sourceparts/source.part3 /tmp/sourceparts/source.part4 > /tmp/source.b64 && \
    echo 'c459776ce17e06efb46793cff0f4a78bd0ef9f7811b93b6596a7fbfec981eb49  /tmp/source.b64' | sha256sum -c - && \
    base64 -d /tmp/source.b64 > /tmp/source.tar.br && \
    echo 'd22bbe981247bc8767a344c6455d2af13b08ac45d91879cc5079ad4ea27ca228  /tmp/source.tar.br' | sha256sum -c - && \
    python -m pip install --no-cache-dir brotli && \
    python -c "import brotli,tarfile,io,pathlib; tarfile.open(fileobj=io.BytesIO(brotli.decompress(pathlib.Path('/tmp/source.tar.br').read_bytes())),mode='r:').extractall('/app',filter='data')" && \
    pip install --no-cache-dir -r requirements.txt && \
    groupadd --system xsgps && useradd --system --gid xsgps --home /app xsgps && \
    mkdir -p /tmp/xsgps-builder-jobs && chmod 700 /tmp/xsgps-builder-jobs && \
    chown -R xsgps:xsgps /app /tmp/xsgps-builder-jobs && rm -rf /tmp/sourceparts /tmp/source.b64 /tmp/source.tar.br
USER xsgps
EXPOSE 8080
CMD ["sh", "-c", "exec uvicorn server:app --host 0.0.0.0 --port ${PORT:-8080} --workers 1 --proxy-headers"]
