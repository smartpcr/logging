FROM mcr.microsoft.com/dotnet/core/aspnet:2.2 AS base
WORKDIR /app
EXPOSE 80

FROM mcr.microsoft.com/dotnet/core/sdk:2.2 AS build
WORKDIR /src
COPY ["Generator.Api.csproj", "."]
RUN dotnet restore "Generator.Api.csproj"
COPY . .
RUN dotnet build "Generator.Api.csproj" -c Release -o /app

FROM build AS publish
RUN dotnet publish "Generator.Api.csproj" -c Release -o /app

FROM base AS final
ARG client_id
WORKDIR /app
COPY --from=publish /app .
ENTRYPOINT ["dotnet", "Generator.Api.dll"]