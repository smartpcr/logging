FROM microsoft/dotnet:2.2-sdk
ENV NUGET_XMLDOC_MODE skip

# Add support for remote debugging inside Docker
WORKDIR /vsdbg
RUN apt-get update \
    && apt-get install -y --no-install-recommends unzip \
    && rm -rf /var/lib/apt/lists/* \
    && curl -sSL https://aka.ms/getvsdbgsh | bash /dev/stdin -v latest -l /vsdbg

# Install NodeJS
ENV NODE_VERSION 8.11.3
ENV NODE_DOWNLOAD_SHA 1ea408e9a467ed4571730e160993f67a100e8c347f6f9891c9a83350df2bf2be  
RUN curl -SL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.gz" --output nodejs.tar.gz \
    && echo "$NODE_DOWNLOAD_SHA nodejs.tar.gz" | sha256sum -c - \
    && tar -xzf "nodejs.tar.gz" -C /usr/local --strip-components=1 \
    && rm nodejs.tar.gz \
    && ln -s /usr/local/bin/node /usr/local/bin/nodejs

# Minimal file copies for package restore
WORKDIR /app
COPY . ./
RUN dotnet restore ./App.Metrics.Reporting.Socket/
RUN dotnet restore ./web/

# Full file copy for build

RUN dotnet publish ./web -o ../out

CMD ["dotnet", "./out/Web.dll"]
