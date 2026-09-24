FROM eclipse-temurin:17-jdk-jammy
ENV DEBIAN_FRONTEND=noninteractive
ENV ANDROID_HOME=/opt/android-sdk
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-venv python3-pip unzip zip wget curl ca-certificates apktool && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /opt/android-sdk/cmdline-tools /opt/xsgps && wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O /tmp/sdk.zip && unzip -q /tmp/sdk.zip -d /opt/android-sdk/cmdline-tools && mv /opt/android-sdk/cmdline-tools/cmdline-tools /opt/android-sdk/cmdline-tools/latest && rm /tmp/sdk.zip
ENV PATH="/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/build-tools/35.0.0:/opt/gradle/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
RUN yes | sdkmanager --sdk_root=/opt/android-sdk --licenses >/dev/null || true
RUN sdkmanager --sdk_root=/opt/android-sdk "platforms;android-35" "build-tools;35.0.0"
RUN wget -q https://services.gradle.org/distributions/gradle-8.9-bin.zip -O /tmp/gradle.zip && unzip -q /tmp/gradle.zip -d /opt && mv /opt/gradle-8.9 /opt/gradle && rm /tmp/gradle.zip
WORKDIR /src
COPY android/build.gradle android/settings.gradle android/gradle.properties ./android/
COPY android/xsgpslib ./android/xsgpslib
RUN cd android && gradle --no-daemon :xsgpslib:assembleRelease && unzip -p xsgpslib/build/outputs/aar/xsgpslib-release.aar classes.jar > /opt/xsgps/classes.jar && cp xsgpslib/src/main/assets/xsgps_map.html /opt/xsgps/xsgps_map.html && mkdir -p /opt/xsgps/dex && d8 --min-api 26 --lib /opt/android-sdk/platforms/android-35/android.jar --output /opt/xsgps/dex /opt/xsgps/classes.jar && mv /opt/xsgps/dex/classes.dex /opt/xsgps/classes.dex
COPY builder/requirements.txt /src/builder/requirements.txt
RUN python3 -m venv /opt/venv && /opt/venv/bin/pip install --no-cache-dir -r /src/builder/requirements.txt
COPY builder /src/builder
WORKDIR /src/builder
ENV PYTHONUNBUFFERED=1
CMD ["sh","-c","exec /opt/venv/bin/uvicorn server:app --host 0.0.0.0 --port $PORT --workers 1"]
