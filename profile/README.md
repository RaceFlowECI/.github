# RaceFlowECI

> Organización GitHub del proyecto **RaceFlow** — ECI · Arquitecturas de Software (ARSW)

---

## Contenido

- [Descripción](#descripción)
- [Repositorios](#repositorios)
- [Stack tecnológico](#stack-tecnológico)
- [Arquitectura (C4)](#arquitectura-c4)
- [Observabilidad](#observabilidad)

---

## Descripción

**RaceFlow** es una plataforma web de **salas de entrenamiento colaborativas en tiempo real**
para deportes de cronometraje (ciclismo, atletismo, triatlón).

Los atletas crean o se unen a salas mediante un código, transmiten su posición GPS en vivo
desde el navegador, ven un mapa compartido con todos los participantes, consultan el ranking
actualizado al instante y envían reacciones durante la sesión.

Al finalizar, cada sesión queda persistida y disponible como historial para análisis posterior.

**Contexto académico:** proyecto integrador de la materia *Arquitecturas de Software (ARSW)*
de la Escuela Colombiana de Ingeniería Julio Garavito.

---

## Repositorios

| Repositorio | Puerto | Responsabilidad |
|---|---|---|
| [`raceflow-frontend`](https://github.com/RaceFlowECI/raceflow-frontend) | — | SPA React + TypeScript + Leaflet.js: mapa en vivo, ranking, reacciones, historial |
| [`raceflow-api-gateway`](https://github.com/RaceFlowECI/raceflow-api-gateway) | 8080 | Punto de entrada único — enruta REST y WebSocket, valida JWT |
| [`raceflow-auth-service`](https://github.com/RaceFlowECI/raceflow-auth-service) | 8081 | Registro, login y emisión de tokens JWT |
| [`raceflow-room-service`](https://github.com/RaceFlowECI/raceflow-room-service) | 8082 | Ciclo de vida de salas: creación, ingreso por código, participantes |
| [`raceflow-realtime-service`](https://github.com/RaceFlowECI/raceflow-realtime-service) | 8083 | WebSocket + cómputo de ranking + difusión en tiempo real (escala horizontal) |
| [`raceflow-session-service`](https://github.com/RaceFlowECI/raceflow-session-service) | 8084 | Persistencia de sesiones finalizadas e historial |
| [`raceflow-metrics-service`](https://github.com/RaceFlowECI/raceflow-metrics-service) | 8085 | KPIs de negocio calculados desde eventos del broker |
| [`raceflow-observability`](https://github.com/RaceFlowECI/raceflow-observability) | — | Stack Docker Compose: Prometheus, Grafana, Loki, Tempo, Alertmanager |