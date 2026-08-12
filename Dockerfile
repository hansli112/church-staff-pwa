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

# 下載 Flutter SDK。版本固定，與 .github/workflows/deploy-flutter-pwa.yml
# 的 FLUTTER_VERSION 保持一致；跟著 stable 浮動會讓 image 某天無預警壞掉。
ARG FLUTTER_VERSION=3.41.0
ENV FLUTTER_HOME="/usr/local/flutter"
RUN git clone --depth 1 https://github.com/flutter/flutter.git \
    -b ${FLUTTER_VERSION} $FLUTTER_HOME

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

# CI 那條路徑會在 build 前生出 web/version.json，App 的 AppVersionService
# 就是讀它來顯示「上次更新」。自架這條原本沒有這一步，/version.json 直接 404，
# 版本日期永遠是空的。兩條部署路徑的產物要一致。
RUN set -eu; \
    GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; \
    mkdir -p web; \
    printf '{\n  "version": "docker-%s",\n  "build_number": "0",\n  "branch": "docker",\n  "generated_at": "%s"\n}\n' \
      "$(date -u +%Y%m%d%H%M%S)" "$GENERATED_AT" > web/version.json

# 建置時注入的設定。FIREBASE_* 少給的話，編出來的 App 連 Firebase 都
# 初始化不了（原本這裡只傳了 VAPID key，等於產出不能用的 image）。
ARG FCM_WEB_VAPID_KEY=""
ARG FIREBASE_API_KEY=""
ARG FIREBASE_AUTH_DOMAIN=""
ARG FIREBASE_PROJECT_ID=""
ARG FIREBASE_STORAGE_BUCKET=""
ARG FIREBASE_MESSAGING_SENDER_ID=""
ARG FIREBASE_APP_ID=""
ARG FIREBASE_MEASUREMENT_ID=""
ARG GOOGLE_CALENDAR_API_KEY=""
ARG GOOGLE_CALENDAR_ID=""

# 編譯 Web 版本 (Release Mode)
# 每個 Firebase.initializeApp 必要的欄位都要檢查 —— 只擋 API key 的話，
# 少給 projectId 一樣會編出一個在瀏覽器裡開不起來的 image。檢查不通過時
# `exit 1` 會直接結束這個 RUN 的 shell，後面的 flutter build 不會跑到。
#
# --dart-define 的每個值都要加引號：GOOGLE_CALENDAR_ID 這種可能帶空白的值
# 沒加引號會被 shell 拆成兩個參數，flutter 收到殘缺的 define 卻照樣編過，
# 錯誤要到執行期才浮出來。
RUN for required in FIREBASE_API_KEY FIREBASE_AUTH_DOMAIN FIREBASE_PROJECT_ID \
                    FIREBASE_MESSAGING_SENDER_ID FIREBASE_APP_ID; do \
      eval "value=\${$required}"; \
      if [ -z "$value" ]; then \
        echo "ERROR: $required build-arg is empty; the image would be non-functional." >&2; \
        exit 1; \
      fi; \
    done; \
    flutter build web --release --base-href / --no-web-resources-cdn \
    --dart-define=FCM_WEB_VAPID_KEY="${FCM_WEB_VAPID_KEY}" \
    --dart-define=FIREBASE_API_KEY="${FIREBASE_API_KEY}" \
    --dart-define=FIREBASE_AUTH_DOMAIN="${FIREBASE_AUTH_DOMAIN}" \
    --dart-define=FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID}" \
    --dart-define=FIREBASE_STORAGE_BUCKET="${FIREBASE_STORAGE_BUCKET}" \
    --dart-define=FIREBASE_MESSAGING_SENDER_ID="${FIREBASE_MESSAGING_SENDER_ID}" \
    --dart-define=FIREBASE_APP_ID="${FIREBASE_APP_ID}" \
    --dart-define=FIREBASE_MEASUREMENT_ID="${FIREBASE_MEASUREMENT_ID}" \
    --dart-define=GOOGLE_CALENDAR_API_KEY="${GOOGLE_CALENDAR_API_KEY}" \
    --dart-define=GOOGLE_CALENDAR_ID="${GOOGLE_CALENDAR_ID}"

# 與 CI 相同：把版本號填進 cache_sw.js，並把 Firebase 設定填進推播 SW。
# 少了這步，自架版的 SW cache 永遠不會失效，使用者會卡在第一次載入的版本。
#
# 跟 CI 一樣要 fail-fast。sed 沒對到 placeholder 時退出碼還是 0，image 會
# 順利 build 完、nginx 也照常起來，只是 SW 帶著字面上的 __BUILD_VERSION__
# 與 __FIREBASE_API_KEY__ 上線 —— 快取永不失效、背景推播無聲失效，
# 兩件事都要等使用者回報才會知道。
RUN set -eu; \
    for placeholder in __BUILD_VERSION__ __VENDOR_VERSION__; do \
      grep -q "$placeholder" build/web/cache_sw.js \
        || { echo "ERROR: $placeholder not found in build/web/cache_sw.js" >&2; exit 1; }; \
    done; \
    for placeholder in __FIREBASE_API_KEY__ __FIREBASE_AUTH_DOMAIN__ \
                       __FIREBASE_PROJECT_ID__ __FIREBASE_STORAGE_BUCKET__ \
                       __FIREBASE_MESSAGING_SENDER_ID__ __FIREBASE_APP_ID__ \
                       __FIREBASE_MEASUREMENT_ID__; do \
      grep -q "$placeholder" build/web/firebase-messaging-sw.js \
        || { echo "ERROR: $placeholder not found in build/web/firebase-messaging-sw.js" >&2; exit 1; }; \
    done; \
    BUILD_VERSION="$(date -u +%Y%m%d%H%M%S)"; \
    sed -i \
      -e "s|__BUILD_VERSION__|${BUILD_VERSION}|g" \
      -e "s|__VENDOR_VERSION__|flutter-${FLUTTER_VERSION}|g" \
      build/web/cache_sw.js; \
    sed -i \
      -e "s|__FIREBASE_API_KEY__|${FIREBASE_API_KEY}|g" \
      -e "s|__FIREBASE_AUTH_DOMAIN__|${FIREBASE_AUTH_DOMAIN}|g" \
      -e "s|__FIREBASE_PROJECT_ID__|${FIREBASE_PROJECT_ID}|g" \
      -e "s|__FIREBASE_STORAGE_BUCKET__|${FIREBASE_STORAGE_BUCKET}|g" \
      -e "s|__FIREBASE_MESSAGING_SENDER_ID__|${FIREBASE_MESSAGING_SENDER_ID}|g" \
      -e "s|__FIREBASE_APP_ID__|${FIREBASE_APP_ID}|g" \
      -e "s|__FIREBASE_MEASUREMENT_ID__|${FIREBASE_MEASUREMENT_ID}|g" \
      build/web/firebase-messaging-sw.js; \
    if grep -n '__BUILD_VERSION__\|__VENDOR_VERSION__' build/web/cache_sw.js \
       || grep -n '__FIREBASE_[A-Z_]*__' build/web/firebase-messaging-sw.js; then \
      echo "ERROR: placeholders remain after substitution" >&2; exit 1; \
    fi

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
