# Despliegue en producción — RaceFlow

> Última actualización: 2026-07-09. Sistema completo verificado funcionando end-to-end en producción (registro, salas, mapa y ranking probados desde dispositivo móvil real).

## Visión general

Todo el sistema corre en **Microsoft Azure** bajo una sola suscripción y un solo grupo de recursos (`rg-raceflow-prod`, región Mexico Central). El despliegue de los 7 repositorios (6 microservicios + frontend) sigue el mismo patrón uniforme:

```
push a main  →  GitHub Actions  →  Azure
```

Ningún artefacto se despliega manualmente: el pipeline compila, ejecuta pruebas (JaCoCo ≥85%), pasa el Quality Gate de SonarCloud y solo entonces despliega.

```
                        ┌─────────────────────────────┐
   Usuario (móvil/web)  │  Azure Static Web Apps      │
  ──────────────────────►  raceflow-frontend (React)  │
                        └──────────┬──────────────────┘
                                   │ HTTPS (REST)          WSS (WebSocket)
                                   ▼                          │
                        ┌─────────────────────┐               │
                        │  API Gateway :8080  │               │
                        │  /api/auth/**  ─────┼──► auth-service :8081
                        │  /api/rooms/** ─────┼──► realtime-service :8083 ◄──┘
                        └─────────────────────┘         │        ▲
                                                        │ gRPC :9090
                                                        ▼        │
                                              auth-service (UserProfileService)
```

## Recursos de Azure

| Recurso | Tipo | Notas |
|---|---|---|
| `raceflow-asp` | App Service Plan (Linux, **Basic B3 × 2 workers**, per-site scaling) | Aloja las 6 apps backend en 2 instancias físicas con balanceo de cargas (ver sección "Balanceo de cargas"). Empezó en B1, se subió a B2 y finalmente a B3 (~7 GB RAM por worker) porque 6 JVMs de Spring Boot concurrentes saturaban los tiers menores (memoria al 90-98%). |
| `raceflow-gateway` | Web App (Java 21) | Puerto 8080. Spring Cloud Gateway (WebFlux). |
| `raceflow-auth-svc` | Web App (Java 21) | Puerto 8081. También expone gRPC interno en 9090. |
| `raceflow-room-svc` | Web App (Java 21) | Puerto 8082. |
| `raceflow-realtime-svc` | Web App (Java 21) | Puerto 8083. WebSockets habilitados. |
| `raceflow-session-svc` | Web App (Java 21) | Puerto 8084. |
| `raceflow-metrics-svc` | Web App (Java 21) | Puerto 8085. |
| `raceflow-frontend` | **Static Web App** (Free) | React + Vite servido desde CDN global. |
| `raceflow-db-server` | PostgreSQL Flexible Server | 4 bases: `raceflow_auth_db`, `raceflow_room_db`, `raceflow_session_db`, `raceflow_metrics_db`. |
| `raceflow-redis` | Azure Redis Enterprise | TLS obligatorio + clave de acceso. |
| `raceflow-rabbitmq` | Container Instance | Broker AMQP (5672) + consola de administración (15672). |
| `raceflow-keyvault` | Key Vault (RBAC) | Secretos: JWT, contraseña de BD, credenciales RabbitMQ, clave Redis. Las 5 apps de negocio acceden vía Managed Identity con rol `Key Vault Secrets User`. |

### URLs de producción

| Componente | URL |
|---|---|
| **Frontend** | https://lively-rock-0066b1e0f.7.azurestaticapps.net |
| API Gateway | https://raceflow-gateway-g8csc0dfh0dxhcax.mexicocentral-01.azurewebsites.net |
| auth-service | https://raceflow-auth-svc-etcwe5asgrhtfqad.mexicocentral-01.azurewebsites.net |
| room-service | https://raceflow-room-svc-aqgybpeffvb0cvbn.mexicocentral-01.azurewebsites.net |
| realtime-service | https://raceflow-realtime-svc-h4fvhydkd2gthheb.mexicocentral-01.azurewebsites.net |
| session-service | https://raceflow-session-svc-fedte8c0f7frf2dp.mexicocentral-01.azurewebsites.net |
| metrics-service | https://raceflow-metrics-svc-d9bxepdgbpfnf2fe.mexicocentral-01.azurewebsites.net |

> Nota: Azure genera hostnames con sufijo único (`-g8csc0dfh0dxhcax`, etc.). Los hostnames "cortos" (`raceflow-gateway.azurewebsites.net`) **no existen** — ver lección #5 abajo.

## Pipeline de CI/CD (backend, idéntico en los 6 repos)

```
PR o push a main
  ├─ 1. Compile          (mvn compile, Java 21)
  ├─ 2. Tests + JaCoCo    (gate: ≥85% cobertura de líneas)
  ├─ 3. SonarCloud        (Quality Gate obligatorio)
  └─ 4. Deploy a Azure    (solo en push a main; azure/webapps-deploy@v3
                           con publish profile por repo)
```

Ramas: `feature/*` → PR a `develop` → PR `develop` → `main`. El deploy solo se dispara desde `main`.

## Pipeline del frontend

`.github/workflows/azure-swa-deploy.yml` en `raceflow-frontend`:

1. `pnpm install --frozen-lockfile` (el proyecto usa **pnpm**, no npm)
2. `pnpm run build` — el build de Vite incrusta las URLs de producción:
   - `VITE_API_AUTH` → auth-service
   - `VITE_API_RT` → realtime-service
   - `VITE_WS_URL` → `wss://` realtime-service
3. `Azure/static-web-apps-deploy` (anclada a SHA de commit, exigencia de SonarCloud S7637) sube `dist/` con el token guardado como secret `AZURE_STATIC_WEB_APPS_API_TOKEN`.

Los PRs generan **entornos de preview** efímeros que se destruyen al cerrar el PR. `staticwebapp.config.json` define el fallback SPA (`/index.html`) para que las rutas de React Router funcionen al recargar.

### Optimización de assets estáticos (logo)

El logo de marca (`public/logo.png`, usado en el login) y el favicon se generaron con **Python +
Pillow** a partir del arte original (1024×1024, 1.4 MB) — demasiado pesado para servirlo tal
cual en una app móvil, cuando el bundle de JS completo de la app pesa ~104 KB gzipped.

```python
from PIL import Image
img = Image.open("icono-front.png")
img.resize((512, 512), Image.LANCZOS).save("public/logo.png", optimize=True)     # -> 120 KB
img.resize((64, 64), Image.LANCZOS).save("public/favicon.png", optimize=True)    # -> 4 KB
```

- **Tamaño de salida**: regla de ~2× el tamaño de despliegue (pantallas de alta densidad). El
  logo se muestra a 110px en el login → 512px alcanza; el favicon se ve a 16-32px → 64px basta.
- **`Image.LANCZOS`**: algoritmo de remuestreo que conserva mejor bordes y detalle al reducir,
  frente a alternativas más rápidas pero borrosas (nearest, bilinear).
- **`optimize=True`**: compresión PNG sin pérdida (mismo píxel a píxel, menos bytes) — el
  codificador prueba varias configuraciones y se queda con la más compacta.

## Justificación: ¿por qué Azure Static Web Apps y no Vercel?

Decisión evaluada explícitamente:

- **Coherencia**: todo el backend ya corre en Azure. Un solo proveedor significa una consola, una identidad, una facturación y una historia arquitectónica consistente.
- **Mismo patrón de CI/CD**: GitHub Actions → Azure, idéntico a los 6 microservicios.
- **Costo**: tier Free (CDN global, SSL, 100 GB/mes) dentro de la misma suscripción de estudiante.
- Vercel/Netlify/Firebase Hosting son plataformas robustas y válidas, pero su ventaja (DX para Next.js, ecosistema propio) no aplica aquí y habrían introducido un segundo proveedor sin necesidad técnica.

## Balanceo de cargas

El plan `raceflow-asp` corre con **2 workers** (2 instancias físicas) y `perSiteScaling`
habilitado, lo que permite decidir por servicio en cuántas instancias corre:

| Servicio | Instancias | Razón |
|---|---|---|
| gateway, auth, room, session, metrics | **2** | Son *stateless* (todo su estado vive en PostgreSQL/Redis/RabbitMQ), así que cualquier instancia puede atender cualquier petición. |
| realtime-service | **1** (fijado) | Guarda el estado vivo de las salas **en memoria** (`ConcurrentHashMap` + sesiones WebSocket). Con 2 instancias, dos atletas de la misma sala podrían caer en instancias distintas y no verse. |

**Quién balancea**: el front-end de Azure App Service — un balanceador L7 integrado que
distribuye las peticiones entrantes entre las instancias sanas de cada app. No hay que
provisionar ni configurar un recurso aparte (a diferencia de un Application Gateway o un
Load Balancer clásico). `clientAffinityEnabled` está en `false` en los servicios stateless:
sin sesiones pegajosas, cada petición puede ir a cualquier instancia, que es la distribución
más pareja posible y es seguro precisamente porque son stateless.

**Cómo se configuró**:

```bash
az appservice plan update --name raceflow-asp -g rg-raceflow-prod \
  --number-of-workers 2 --set perSiteScaling=true
az webapp config set --name <app> -g rg-raceflow-prod --number-of-workers 2   # las 5 stateless
az webapp config set --name raceflow-realtime-svc -g rg-raceflow-prod --number-of-workers 1
```

**Verificación**: `az webapp list-instances` muestra las 2 instancias del plan; los 6 servicios
reportan `{"status":"UP"}` tras el escalado y la memoria promedio quedó en ~65-75% entre ambos
workers.

**Camino para escalar realtime-service** (documentado, no implementado): mover el estado de las
salas de la memoria a Redis (el ranking ya se cachea ahí) y publicar los eventos de posición por
RabbitMQ para que todas las instancias vean las actualizaciones — con eso dejaría de ser
stateful y podría correr en N instancias como los demás.

**Health checks (alta disponibilidad a nivel de instancia)**: los 6 servicios tienen configurado
el *Health Check* de App Service apuntando a `/actuator/health` (que agrega el estado de
PostgreSQL, Redis y RabbitMQ). La plataforma consulta esa ruta cada minuto **en cada instancia**:
si una instancia responde mal, el balanceador **la saca de rotación** (el tráfico sigue fluyendo
por la instancia sana) y App Service la reinicia si no se recupera. Es el mismo mecanismo
target-group + health check del patrón clásico de alta disponibilidad, provisto por la
plataforma:

```bash
az webapp config set --name <app> -g rg-raceflow-prod \
  --generic-configurations '{"healthCheckPath": "/actuator/health"}'
```

**Auto-escalado (decisión de alcance)**: las reglas de autoscale por métrica (p. ej. CPU>70% →
agregar instancia) requieren tier **Standard** en App Service; en Basic el escalado es manual
(`--number-of-workers N`). Decisión tomada: quedarse en B3 con escalado manual por costo
(Standard ≈ 2× el precio contra el crédito de estudiante); la arquitectura ya lo soporta — los
servicios son stateless y el balanceo es automático — así que activar autoscale sería solo el
cambio de tier + una regla de Azure Monitor, como la demostrada en el laboratorio IaaS
(`rg-raceflow-lab`, autoscale CPU>70% en el VMSS).

## Laboratorio: Alta disponibilidad y escalabilidad con Azure Load Balancer (IaaS)

Réplica en Azure de los laboratorios del curso hechos en AWS ("Alta Disponibilidad con
Application Load Balancer" y "Escalabilidad"), en un grupo de recursos aparte
(`rg-raceflow-lab`) que no toca RaceFlow. Demuestra los mismos conceptos una capa más abajo
(IaaS) de donde vive RaceFlow (PaaS):

| Concepto del lab (AWS) | Implementación en Azure |
|---|---|
| EC2 | VM Scale Set `raceflow-lab-vmss` (2× Standard_B1s, Ubuntu 22.04 + nginx) |
| Application Load Balancer | **Azure Load Balancer Standard** `raceflow-lab-lb` (IP pública 68.155.157.45) |
| Target Group | Backend Pool `lab-backend-pool` |
| Health Check | Health Probe HTTP `/` cada 5s |
| Auto Scaling Group + CloudWatch | Autoscale `lab-autoscale`: CPU>70% (5min) → 3 instancias; CPU<30% → 2 |
| Security Group | NSG `raceflow-lab-vmssNSG` (regla `allow-http` puerto 80) |

**Verificación realizada**: `curl` consecutivos a la IP del balanceador alternan entre
`Instancia racef33db000000` e `Instancia racef33db000001` (cada instancia sirve una página con
su hostname) — la misma evidencia que pedía el lab de AWS al recargar el navegador.

**Nota conceptual**: Azure Load Balancer es L4 (reparte conexiones TCP por hash de 5-tupla),
mientras el ALB de AWS es L7. El equivalente L7 exacto en Azure es Application Gateway
(descartado por costo, ~$6/día). En RaceFlow (PaaS) este balanceo lo hace el front-end
integrado de App Service — este laboratorio muestra cómo se construye a mano lo que la
plataforma da hecho.

**Diagnóstico curioso durante el montaje**: el health probe marcaba las instancias como no
sanas aunque nginx respondía. El access log reveló `GET /C:/Program%20Files/Git/` — Git Bash
(MSYS) convirtió el path `/` del probe en una ruta de Windows al crearlo por CLI. Se corrigió
recreando el probe con `MSYS_NO_PATHCONV=1`. Lección: cuidado con la conversión de paths de
Git Bash al pasar argumentos que empiezan por `/` a CLIs de Windows.

**Costo y ciclo de vida**: ~$1.30/día mientras exista. Todo el laboratorio se elimina con
`az group delete --name rg-raceflow-lab` sin afectar RaceFlow.

## Configuración crítica por servicio (App Settings)

Cada Web App define, entre otras:

- `WEBSITES_PORT` — puerto real del servicio (8080–8085). **Sin esto, Azure asume el 80 y la app nunca responde** (lección #1).
- `SPRING_DATASOURCE_URL/USERNAME/PASSWORD` — conexión a PostgreSQL (password vía Key Vault reference).
- `SPRING_REDIS_HOST/PORT/PASSWORD/SSL` — Redis Enterprise exige TLS y clave.
- `RABBITMQ_HOST/PORT/USERNAME/PASSWORD` — el broker rechaza el usuario `guest` en conexiones remotas.
- `JWT_SECRET` — vía Key Vault reference.
- Gateway: `AUTH_SERVICE_URL`, `REALTIME_SERVICE_URL` con los hostnames **completos** (con sufijo).

## Lecciones aprendidas (problemas reales resueltos durante el despliegue)

1. **`WEBSITES_PORT` ausente** → las 6 apps daban timeout total aunque el deploy era "exitoso". Azure enruta al puerto 80 por defecto; hay que declarar el puerto real de cada servicio.
2. **HTTP 200 engañoso** → la página placeholder de Azure ("Hey, Java developers!") responde 200 en cualquier ruta. Verificar siempre el *cuerpo* de la respuesta, no solo el código.
3. **Memoria insuficiente** → 6 JVMs Spring Boot no caben en B1 (~1.75 GB) ni cómodamente en B2 (~3.5 GB). B3 estabilizó la memoria en ~30%.
4. **Nombres de variables de entorno inconsistentes** → los servicios leían `RABBITMQ_USER`/`REDIS_HOST` pero Azure provisionaba `RABBITMQ_USERNAME`/`SPRING_REDIS_HOST`. Sin la credencial, Spring cae al default (`guest`/localhost) y el health check marca `DOWN`. Moraleja: contrato de nombres de env vars único y documentado.
5. **Hostnames con sufijo único** → el gateway apuntaba a `raceflow-auth-svc.azurewebsites.net` (no existe). Azure genera `raceflow-auth-svc-<sufijo>.<región>.azurewebsites.net`.
6. **JAR corrupto por colisión de operaciones** → un deploy concurrente con un restart/resize dejó un `app.jar` truncado (~21 MB menos) que el contenedor no podía arrancar. Se resolvió re-ejecutando el workflow de deploy.
7. **Health checks de Actuator como fuente de verdad** → `/actuator/health` agrega el estado de BD, Redis y RabbitMQ; un `DOWN` señala exactamente qué dependencia falla (visible con detalle en los logs de la app).
8. **CI verde ≠ código actual en producción** → el frontend desplegado mostraba datos hardcodeados (salas y atletas de maqueta) aunque el pipeline estaba verde: la versión conectada al backend real se había fusionado a `develop` pero nunca se promovió a `main`, y el deploy sale de `main`. El pipeline desplegaba, correctamente, código viejo. Se corrigió promoviendo `develop` → `main` (PR raceflow-frontend#10), eliminando de paso la lista mock de "salas activas" (no existe endpoint para listar salas). Bonus: al pasar el código real por el pipeline, SonarCloud bloqueó una vulnerabilidad genuina (código de sala y token insertados sin validar en la URL del WebSocket, regla S8480) que se corrigió con validación de formato y encoding. Moraleja doble: verificar el *contenido* funcional desplegado (probar el flujo real, no solo el status del pipeline) y mantener la promoción `develop` → `main` como paso explícito del proceso de release.

## Verificación end-to-end realizada

- Los 7 componentes responden HTTP 200 con contenido real.
- Los 6 backend reportan `{"status":"UP"}` en `/actuator/health` (BD + Redis + RabbitMQ conectados).
- Enrutamiento del gateway verificado: `POST /api/auth/login` a través del gateway devuelve exactamente la misma respuesta que auth-service directo.
- Preflight CORS verificado desde el dominio del frontend contra auth-service.
- Flujo funcional completo (registro → login → crear sala → unirse → mapa → ranking en vivo por WebSocket) probado desde un dispositivo móvil real.
