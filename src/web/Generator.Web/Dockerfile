FROM rrdpdevacr.azureacr.io/dotnet/core/aspnet:2.2 AS base
WORKDIR /app
EXPOSE 80

FROM rrdpdevacr.azureacr.io/dotnet/core/sdk:2.2 AS build
WORKDIR /src
COPY . .
WORKDIR /src/src/services/Generator.API
RUN dotnet restore -nowarn:msb3202,nu1503
RUN dotnet build --no-restore -c Release -o /app

FROM build as unittest
WORKDIR /src/src/services/Generator.Api.UnitTests

FROM build as functionaltest
WORKDIR /src/src/services/Generator.Api.IntegrationTests

FROM build AS publish
RUN dotnet publish --no-restore -c Release -o /app

FROM base AS final
WORKDIR /app
COPY --from=publish /app .
ENTRYPOINT ["dotnet", "Generator.API.dll"]