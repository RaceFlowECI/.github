workspace "RaceFlow" "Salas de entrenamiento colaborativas en tiempo real para deportes de cronometraje" {

    !identifiers hierarchical

    model {
        athlete = person "Atleta" "Crea o se une a salas, transmite GPS en vivo, ve mapa y ranking, envía reacciones y consulta su historial."

        mapsService = softwareSystem "Servicio de Mapas" "Provee los tiles del mapa para visualizar posiciones en vivo (Leaflet + OpenStreetMap)." {
            tags "External"
        }

        geolocationApi = softwareSystem "API de Geolocalización" "API del navegador que provee las coordenadas GPS del dispositivo del atleta." {
            tags "External"
        }

        raceflow = softwareSystem "RaceFlow" "Plataforma web de salas de entrenamiento colaborativas en tiempo real para deportes de cronometraje." {

            webapp = container "Web Application" "Interfaz del atleta: mapa en vivo, ranking, reacciones, registro, perfil e historial." "React + TypeScript + Leaflet.js" {
                tags "Web Browser"
            }

            gateway = container "API Gateway" "Punto de entrada único. Enruta peticiones REST y conexiones WebSocket, valida el JWT. Replicado para no ser punto único de falla." "Spring Cloud Gateway"

            authService = container "Auth Service" "Registro, inicio de sesión y emisión de tokens JWT." "Java 21 + Spring Boot"
            roomService = container "Room Service" "Ciclo de vida de salas: creación, ingreso por código, participantes." "Java 21 + Spring Boot"

            realtimeService = container "Realtime / Ranking Service" "Recibe posiciones GPS por WebSocket, recalcula el ranking y difunde a los participantes. Escala horizontalmente." "Java 21 + Spring Boot + spring-websocket" {
                wsHandler = component "RoomWebSocketHandler" "Gestiona las conexiones WebSocket de cada sala: recibe posiciones y reacciones, difunde (broadcast) a los participantes suscritos." "Spring WebSocket Handler"
                positionController = component "PositionIngestor" "Valida cada posición GPS entrante (descarta saltos imposibles o datos manipulados) antes de procesarla." "Spring Component"
                rankingService = component "RankingService" "Recalcula el ranking de la sala ante cada posición. Usa la estrategia de ranking según el deporte." "Spring Service"
                rankingStrategy = component "RankingStrategy" "Interfaz de cálculo de ranking. Implementaciones intercambiables por deporte (distancia, velocidad)." "Strategy (interfaz)"
                roomStateClient = component "RoomStateClient" "Lee y actualiza el estado de sala y el ranking en Redis con operaciones atómicas; fuente única entre réplicas." "Spring Data Redis"
                eventPublisher = component "EventPublisher" "Publica eventos de dominio (sesión finalizada, reacciones) en el broker." "Spring AMQP"
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
        athlete -> geolocationApi "Obtiene coordenadas GPS de su dispositivo"

        // ----- Relaciones de contenedores (Nivel 2) -----
        athlete -> raceflow.webapp "Accede desde el navegador" "HTTPS"
        raceflow.webapp -> mapsService "Solicita tiles del mapa" "HTTPS"
        raceflow.webapp -> raceflow.gateway "Peticiones REST (registro, salas, historial, KPIs)" "JSON/HTTPS"
        raceflow.webapp -> raceflow.gateway "Canal de tiempo real: posiciones, ranking, reacciones" "WebSocket"

        raceflow.gateway -> raceflow.authService "Enruta autenticación" "JSON/HTTPS"
        raceflow.gateway -> raceflow.roomService "Enruta gestión de salas" "JSON/HTTPS"
        raceflow.gateway -> raceflow.realtimeService "Enruta el canal de tiempo real" "WebSocket"
        raceflow.gateway -> raceflow.sessionService "Enruta consultas de historial" "JSON/HTTPS"
        raceflow.gateway -> raceflow.metricsService "Enruta consultas de KPIs" "JSON/HTTPS"

        raceflow.realtimeService -> raceflow.redis "Lee y actualiza el estado de sala y el ranking (operaciones atómicas)" "Redis protocol"

        raceflow.authService -> raceflow.authDb "Lee/escribe" "JDBC"
        raceflow.roomService -> raceflow.roomDb "Lee/escribe" "JDBC"
        raceflow.sessionService -> raceflow.sessionDb "Lee/escribe" "JDBC"
        raceflow.metricsService -> raceflow.metricsDb "Lee/escribe el read model" "JDBC"

        raceflow.roomService -> raceflow.broker "Publica eventos (sala creada/cerrada)" "AMQP"
        raceflow.realtimeService -> raceflow.broker "Publica eventos (sesión finalizada, reacciones)" "AMQP"
        raceflow.broker -> raceflow.sessionService "Entrega eventos para persistir sesiones" "AMQP"
        raceflow.broker -> raceflow.metricsService "Entrega eventos para actualizar KPIs" "AMQP"

        // ----- Relaciones de componentes (Nivel 3) -----
        raceflow.webapp -> raceflow.realtimeService.wsHandler "Emite posiciones y reacciones; recibe ranking y posiciones" "WebSocket"
        raceflow.realtimeService.wsHandler -> raceflow.realtimeService.positionController "Entrega la posición entrante para validar"
        raceflow.realtimeService.positionController -> raceflow.realtimeService.rankingService "Envía la posición válida para recalcular el ranking"
        raceflow.realtimeService.rankingService -> raceflow.realtimeService.rankingStrategy "Calcula el orden según el deporte"
        raceflow.realtimeService.rankingService -> raceflow.realtimeService.roomStateClient "Lee/actualiza estado y ranking"
        raceflow.realtimeService.roomStateClient -> raceflow.redis "Operaciones atómicas sobre el estado de sala" "Redis protocol"
        raceflow.realtimeService.wsHandler -> raceflow.realtimeService.eventPublisher "Notifica sesión finalizada / reacciones"
        raceflow.realtimeService.eventPublisher -> raceflow.broker "Publica eventos de dominio" "AMQP"
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
