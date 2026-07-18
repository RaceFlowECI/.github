workspace "RaceFlow" "Salas de entrenamiento colaborativas en tiempo real para deportes de cronometraje" {

    !identifiers hierarchical

    model {
        athlete = person "Atleta" "Crea o se une a salas, transmite GPS en vivo, ve mapa y ranking, habla por el chat de voz del grupo y consulta su historial."

        mapsService = softwareSystem "OpenStreetMap" "Servidor público de tiles de mapa consumido vía Leaflet.js, dominio tile.openstreetmap.org. Sin API key ni contrato -- servicio abierto." {
            tags "External"
        }

        geolocationApi = softwareSystem "Geolocation API (W3C)" "API nativa del navegador (navigator.geolocation.watchPosition), no un servicio de terceros: provee las coordenadas GPS del dispositivo del atleta en tiempo real." {
            tags "External"
        }

        raceflow = softwareSystem "RaceFlow" "Plataforma web de salas de entrenamiento colaborativas en tiempo real para deportes de cronometraje." {

            webapp = container "Web Application" "Interfaz del atleta: mapa en vivo, ranking, chat de voz (WebRTC P2P), registro e historial. Servida desde Azure Static Web Apps." "React + TypeScript + Leaflet.js" {
                tags "Web Browser"
            }

            gateway = container "API Gateway" "Punto de entrada REST (/api/**). Replicado en 2 workers tras el balanceador L7 integrado de App Service." "Spring Cloud Gateway"

            authService = container "Auth Service" "Registro, login, JWT (con claim name), amistades (solicitudes/aceptación, persistidas) y servidor gRPC interno :9090." "Java 21 + Spring Boot"
            roomService = container "Room Service" "Placeholder: el ciclo de vida de salas se consolidó en Realtime Service (ver RoomManager). Expone solo /actuator y sus métricas de negocio, reservado para separar esa responsabilidad más adelante." "Java 21 + Spring Boot"

            realtimeService = container "Realtime / Ranking Service" "Posiciones GPS por WebSocket, ranking, señalización del chat de voz WebRTC e invitaciones a salas (en memoria, tan efímeras como la sala). Fijado a 1 instancia." "Java 21 + Spring Boot + spring-websocket" {
                wsHandler = component "RoomWebSocketHandler" "Conexiones WebSocket de cada sala: posiciones GPS, broadcast de ranking y señalización de voz (VOICE_JOIN/LEAVE/OFFER/ANSWER/ICE relevada al peer destino, con anti-suplantación)." "Spring WebSocket Handler"
                roomManager = component "RoomManager" "Estado de salas en memoria (ConcurrentHashMap); resuelve el nombre autoritativo del atleta vía gRPC con fallback." "Spring Service"
                rankingService = component "RankingService" "Recalcula el ranking de la sala ante cada posición. Usa la estrategia de ranking según el deporte." "Spring Service"
                rankingStrategy = component "RankingStrategy" "Interfaz de cálculo de ranking. Implementaciones intercambiables por deporte (distancia, velocidad)." "Strategy (interfaz)"
                grpcAuthClient = component "GrpcAuthClient" "Cliente gRPC hacia auth-service (UserProfileService); timeout 2s y fallback al nombre del cliente." "grpc-java"
                authInterceptor = component "WebSocketAuthInterceptor" "Valida el JWT en el handshake del WebSocket (?token=)." "HandshakeInterceptor"
            }

            sessionService = container "Session / History Service" "Persiste las sesiones finalizadas y permite consultar el historial." "Java 21 + Spring Boot"
            metricsService = container "Metrics Service" "Calcula los 4 KPIs de negocio y métricas técnicas a partir de eventos; expone el dashboard." "Java 21 + Spring Boot"

            broker = container "Event Bus" "Transporta eventos asíncronos entre servicios (sesión cerrada, sala creada, métricas)." "RabbitMQ" {
                tags "Broker"
            }

            redis = container "Estado en memoria" "Estado compartido de salas y ranking; operaciones atómicas; fuente única de verdad entre réplicas." "Redis" {
                tags "Cache"
            }

            authDb = container "Auth DB" "Usuarios y credenciales." "PostgreSQL" {
                tags "Database"
            }
            roomDb = container "Room DB" "Salas y participantes." "PostgreSQL" {
                tags "Database"
            }
            sessionDb = container "Session DB" "Sesiones finalizadas e historial." "PostgreSQL" {
                tags "Database"
            }
            metricsDb = container "Metrics DB" "Read model de KPIs y métricas." "PostgreSQL" {
                tags "Database"
            }
        }

        // ----- Relaciones de contexto (Nivel 1) -----
        athlete -> raceflow "Crea salas, transmite GPS, ve ranking en vivo, envía reacciones, consulta historial" "HTTPS + WebSocket"
        raceflow -> mapsService "Solicita tiles del mapa" "HTTPS"
        raceflow -> geolocationApi "Obtiene coordenadas GPS del dispositivo del atleta" "Browser API"

        // ----- Relaciones de contenedores (Nivel 2) -----
        athlete -> raceflow.webapp "Accede desde el navegador" "HTTPS"
        raceflow.webapp -> mapsService "Solicita tiles del mapa" "HTTPS"
        raceflow.webapp -> geolocationApi "Suscribe watchPosition() para coordenadas GPS en vivo" "Browser API"
        raceflow.webapp -> raceflow.gateway "Peticiones REST (registro, salas, historial, KPIs)" "JSON/HTTPS"
        raceflow.webapp -> raceflow.realtimeService "Canal de tiempo real DIRECTO: posiciones, ranking, señalización de voz" "WebSocket (WSS)"

        raceflow.gateway -> raceflow.authService "Enruta autenticación" "JSON/HTTPS"
        raceflow.gateway -> raceflow.realtimeService "Enruta gestión de salas (/api/rooms/**)" "JSON/HTTPS"
        raceflow.realtimeService -> raceflow.authService "Consulta el nombre autoritativo del atleta (con fallback)" "gRPC :9090"
        raceflow.gateway -> raceflow.sessionService "Enruta consultas de historial" "JSON/HTTPS"
        raceflow.gateway -> raceflow.metricsService "Enruta consultas de KPIs" "JSON/HTTPS"

        raceflow.realtimeService -> raceflow.redis "Lee y actualiza el estado de sala y el ranking (operaciones atómicas)" "Redis protocol"

        raceflow.authService -> raceflow.authDb "Lee/escribe" "JDBC"
        raceflow.roomService -> raceflow.roomDb "Lee/escribe" "JDBC"
        raceflow.sessionService -> raceflow.sessionDb "Lee/escribe" "JDBC"
        raceflow.metricsService -> raceflow.metricsDb "Lee/escribe el read model" "JDBC"

        raceflow.realtimeService -> raceflow.broker "Publica evento room.activated al crear una sala (best-effort, no bloquea si el broker falla)" "AMQP, exchange raceflow.events"
        raceflow.broker -> raceflow.metricsService "Entrega room.activated (cola metrics.room-events, binding room.*) para incrementar KPIs" "AMQP"

        // ----- Relaciones de componentes (Nivel 3) -----
        raceflow.webapp -> raceflow.realtimeService.authInterceptor "Handshake WebSocket con JWT" "WSS"
        raceflow.realtimeService.authInterceptor -> raceflow.realtimeService.wsHandler "Conexión autenticada"
        raceflow.realtimeService.wsHandler -> raceflow.realtimeService.roomManager "Registra sesiones y consulta salas"
        raceflow.realtimeService.wsHandler -> raceflow.realtimeService.rankingService "Recalcula el ranking ante cada posición"
        raceflow.realtimeService.rankingService -> raceflow.realtimeService.rankingStrategy "Calcula el orden según el deporte"
        raceflow.realtimeService.rankingService -> raceflow.redis "Cachea el ranking (TTL 1h)" "Redis protocol"
        raceflow.realtimeService.roomManager -> raceflow.realtimeService.grpcAuthClient "Resuelve el nombre autoritativo"
        raceflow.realtimeService.grpcAuthClient -> raceflow.authService "UserProfileService.getProfile(email)" "gRPC :9090"
    }

    views {
        systemContext raceflow "Contexto" {
            include *
            autoLayout lr
        }

        container raceflow "Contenedores" {
            include *
            autoLayout lr
        }

        component raceflow.realtimeService "Componentes_Realtime" {
            include *
            autoLayout lr
        }

        styles {
            element "Person" {
                shape Person
                background #1A3A5C
                color #FFFFFF
            }
            element "Software System" {
                background #2471A3
                color #FFFFFF
                shape RoundedBox
            }
            element "External" {
                background #999999
                color #FFFFFF
                shape RoundedBox
            }
            element "Container" {
                background #438DD5
                color #FFFFFF
                shape RoundedBox
            }
            element "Component" {
                background #85BBF0
                color #000000
                shape RoundedBox
            }
            element "Web Browser" {
                shape WebBrowser
                background #17C3B2
                color #06303A
            }
            element "Database" {
                shape Cylinder
                background #12557C
                color #FFFFFF
            }
            element "Cache" {
                shape Cylinder
                background #C0392B
                color #FFFFFF
            }
            element "Broker" {
                shape Pipe
                background #6C3483
                color #FFFFFF
            }
            relationship "Relationship" {
                thickness 2
            }
        }
    }

    configuration {
        scope softwaresystem
    }
}
