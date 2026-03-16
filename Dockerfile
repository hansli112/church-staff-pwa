# Stage 1: 建置環境 (使用 build host 以確保 Flutter SDK 相容性與編譯速度)
# 我們產出的是靜態 HTML/JS，所以在哪裡編譯都沒關係
ARG BUILDPLATFORM
FROM --platform=$BUILDPLATFORM ubuntu:22.04 AS builder

# 安裝 Flutter 依賴
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

# 下載 Flutter SDK (Stable Channel)
ENV FLUTTER_HOME="/usr/local/flutter"
RUN git clone https://github.com/flutter/flutter.git -b stable $FLUTTER_HOME

# 設定環境變數
ENV PATH="$FLUTTER_HOME/bin:$FLUTTER_HOME/bin/cache/dart-sdk/bin:${PATH}"

# 預先下載 Dart SDK 與依賴，加速後續構建
RUN flutter config --enable-web

# 設定工作目錄
WORKDIR /app

# 複製專案檔案 (分層複製以利用 Docker Cache)
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# 複製其餘原始碼
COPY . .

# Web Push 的公開 VAPID Key（建置時注入）
ARG FCM_WEB_VAPID_KEY=""

# 編譯 Web 版本 (Release Mode)
RUN flutter build web --release --base-href / \
    --dart-define=FCM_WEB_VAPID_KEY=${FCM_WEB_VAPID_KEY}

# Stage 2: 執行環境 (目標架構 armv7)
# Nginx Alpine 版本支援多架構，包括 linux/arm/v7
FROM nginx:alpine

# 移除預設 Nginx 設定
RUN rm /etc/nginx/conf.d/default.conf

# 複製我們自定義的 Nginx 設定
COPY nginx.conf /etc/nginx/conf.d/default.conf

# 從 Builder 階段複製編譯好的靜態檔案
COPY --from=builder /app/build/web /usr/share/nginx/html

# 開放 80 port
EXPOSE 80

# 啟動 Nginx
CMD ["nginx", "-g", "daemon off;"]
