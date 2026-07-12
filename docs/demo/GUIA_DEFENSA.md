# RaceFlow — Guía para defender el proyecto

> No memorices código. Memoriza el **flujo** y el **porqué** de cada decisión. Si te preguntan
> algo puntual del código y no te acuerdas exacto, está bien decir "la lógica exacta la tengo
> en el repo, pero la idea es..." y explicar el flujo — eso demuestra que entendiste el diseño,
> que es lo que realmente evalúan.

---

## 1. El flujo completo, en una frase por paso

Esto es lo que tienes que poder decir de memoria, sin mirar nada:

1. El atleta se registra → el navegador manda email/password/nombre por HTTP a `auth-service`
2. `auth-service` guarda el usuario en Postgres (contraseña nunca en texto plano, hasheada con BCrypt) y devuelve un **JWT** (un token firmado que dice "este email está autenticado")
3. El frontend guarda ese token y lo manda en cada petición siguiente (`Authorization: Bearer <token>`)
4. El atleta crea una sala → el frontend manda `POST /rooms/create` a `realtime-service`, con el token
5. `realtime-service` valida el token, y en vez de confiar en el nombre que mandó el frontend, **le pregunta a `auth-service`** cuál es el nombre real de ese email — usando **gRPC**, un canal interno que solo hablan los servicios entre sí, nunca el navegador
6. El navegador abre un **WebSocket** hacia `realtime-service` (conexión persistente, no HTTP normal) y empieza a mandar su posición GPS cada vez que se mueve
7. `realtime-service` calcula la distancia recorrida (fórmula de Haversine, distancia entre dos coordenadas GPS) y recalcula el ranking de la sala
8. `realtime-service` **difunde** el ranking actualizado a todos los que están conectados a esa sala por WebSocket — así todos ven lo mismo en tiempo real, sin refrescar la página

Ese es TODO el sistema. Todo lo demás (Gateway, CI/CD, tests) es infraestructura alrededor de este flujo.

---

## 2. Por qué cuatro formas de comunicación distintas (esto es lo que más preguntan)

**Pregunta esperada: "¿Por qué no usaste solo REST para todo?"**

> Porque cada tipo de comunicación tiene un problema distinto que resuelve mejor:
>
> - **REST (HTTP)** — para operaciones puntuales tipo pregunta-respuesta: "regístrame", "crea una sala". El navegador pide algo, el servidor responde, se acaba. Es lo único que un navegador puede hablar sin código especial.
> - **WebSocket** — para datos que cambian todo el tiempo (posición GPS, ranking). Con REST tendrías que estar preguntando "¿hay algo nuevo?" cada segundo (polling), lo cual es ineficiente. WebSocket deja la conexión abierta y el servidor empuja los datos apenas cambian.
> - **gRPC** — para que los servicios se hablen *entre ellos*, nunca con el navegador. Es más rápido que REST porque usa un formato binario (Protocol Buffers) en vez de JSON de texto, y obliga a definir un contrato estricto (`.proto`) — no puedes mandar cualquier cosa, tiene que cumplir el formato exacto.
> - **WebRTC** — para el chat de voz entre atletas. Es el único de los cuatro donde los datos NO pasan por mi servidor: el audio fluye directo de navegador a navegador (peer-to-peer). Mandar audio en vivo por el servidor duplicaría la latencia y me costaría ancho de banda; WebRTC es el estándar del navegador para media en tiempo real (es lo que usan Meet y Discord).

**Pregunta esperada: "¿Cómo funciona la llamada de voz? ¿El audio pasa por tu servidor?"**

> No — y esa es la gracia. WebRTC necesita dos cosas: (1) que los dos navegadores negocien cómo
> conectarse (qué códecs, qué direcciones IP/puertos pueden usar), y (2) el canal de audio en sí.
> La negociación — que se llama **señalización** — viaja por el **WebSocket autenticado que ya
> tenía** la sala: un peer manda su "oferta" (SDP), el otro responde, e intercambian candidatos
> de red (ICE) que descubren con un servidor STUN público. Mi servidor solo **reenvía esos
> mensajes al destinatario correcto** — nunca ve ni toca el audio. Una vez negociado, el audio
> va directo entre los dos dispositivos.
>
> Dos detalles finos que puedo defender:
> - **Anti-suplantación**: el campo "de quién viene" cada mensaje de señalización lo estampa el
>   servidor con la identidad del JWT de la conexión — un cliente no puede fingir ser otro atleta.
> - **Glare avoidance**: si dos peers intentan llamarse al mismo tiempo, la negociación choca.
>   Lo resolví con una regla determinista: en cada par, solo inicia la oferta quien tenga el
>   email lexicográficamente menor; el otro solo responde.
>
> Limitación conocida (honesta): con solo STUN, si ambos dispositivos están detrás de NAT
> corporativo muy restrictivo el P2P puede no conectar; la solución completa es un servidor
> TURN que haga de relay — documentado como mejora futura, no necesario en redes normales.

**Pregunta esperada: "¿Por qué no usaste sockets crudos o RMI, si los vimos en el taller?"**

> - Sockets crudos: tendría que inventar mi propio protocolo de texto (tipo "GET_ROOM:123") y manejar a mano todos los errores que HTTP ya resuelve. No hay ninguna ganancia, solo más trabajo.
> - RMI: exige que el cliente sea Java. Mi cliente es un navegador con React — RMI no puede hablarle a un navegador, así de simple.

---

## 3. El punto más fuerte del proyecto: el gRPC interno

**Pregunta esperada: "¿Para qué sirve exactamente el gRPC que agregaste?"**

> Antes, si yo mandaba `POST /rooms/create` con `{"name": "Cristiano Ronaldo"}`, el sistema me
> creaba la sala con ese nombre sin verificar nada — cualquiera podía mentir sobre su nombre.
>
> Ahora, `realtime-service` recibe la petición, pero antes de guardar el nombre le pregunta a
> `auth-service` — por gRPC, en el puerto 9090, un canal que solo existe entre los dos
> servidores — "¿cuál es el nombre real de este email según tu base de datos?". Si
> `auth-service` responde, usa ESE nombre, ignorando lo que mandó el cliente.
>
> Si `auth-service` está caído o no responde a tiempo, el sistema no se cae — usa el nombre que
> mandó el cliente como respaldo, y deja un log de advertencia. Eso es diseño de resiliencia:
> un servicio interno que falla no debería tumbar toda la operación.

**Si te piden que lo demuestres en vivo**: está en el paso 4 del `DEMO_CHECKLIST.md` — registras con un nombre, creas la sala con otro nombre distinto, y el estado final de la sala muestra el nombre real.

---

## 4. El API Gateway

**Pregunta esperada: "¿Qué hace el Gateway que no podría hacer el frontend directamente?"**

> Sin Gateway, el frontend tendría que saber que auth-service vive en el puerto 8081 y
> realtime-service en el 8083 — si mañana cambio esos puertos o los muevo a otro servidor, hay
> que actualizar el frontend. Con el Gateway, el frontend solo conoce **un** punto de entrada
> (puerto 8080), y el Gateway internamente sabe a quién reenviar cada petición según la ruta
> (`/api/auth/**` va a un lado, `/api/rooms/**` va a otro).

**Pregunta esperada: "¿Por qué el WebSocket no pasa por el Gateway?"**

> Decisión consciente, no descuido: hacer que Spring Cloud Gateway reenvíe WebSocket agrega una
> capa reactiva adicional (buffers, timeouts distintos) que no valía la pena para el alcance de
> este proyecto. El frontend conecta el WebSocket directo a realtime-service. Es un trade-off
> — documenté por qué, en vez de simplemente no hacerlo.

---

## 5. Seguridad

**Pregunta esperada: "¿Cómo sabes que un usuario es quien dice ser?"**

> JWT (JSON Web Token). Cuando haces login, `auth-service` firma un token con una clave secreta
> compartida (solo el backend la conoce) que dice "este email está autenticado, válido por 24
> horas". Cada petición siguiente manda ese token en el header `Authorization`. El backend lo
> valida verificando la firma — si alguien lo modificó, la firma no coincide y se rechaza.
>
> Las contraseñas nunca se guardan en texto plano — se guardan "hasheadas" con BCrypt, un
> algoritmo que las convierte en algo irreversible. Ni yo, viendo la base de datos, puedo saber
> la contraseña real de un usuario.

**Pregunta esperada: "¿Por qué desactivaste CSRF? ¿No es inseguro?"**

> CSRF protege contra ataques que aprovechan que el navegador manda automáticamente las cookies
> de sesión a cualquier sitio. Yo no uso cookies de sesión — uso el header `Authorization` con
> el JWT, y los navegadores NO mandan ese header automáticamente a otros sitios. Entonces el
> ataque que CSRF previene no puede pasar en mi sistema. Por eso está desactivado, y lo dejé
> comentado en el código explicando exactamente esto — SonarCloud (la herramienta de análisis
> de calidad) lo marca como sospechoso si no lo justificas explícitamente.

---

## 6. Testing y calidad

**Pregunta esperada: "¿Cómo garantizas que el código funciona?"**

> Cada servicio tiene un pipeline automático (CI/CD) que corre en cada cambio: primero compila,
> luego corre todos los tests unitarios y exige que cubran al menos el 85% de las líneas de
> código (herramienta JaCoCo), y después pasa un análisis estático (SonarCloud) que busca
> vulnerabilidades y problemas de calidad. Si algo de eso falla, el cambio no se puede fusionar.
>
> Los tests no son solo "que compile" — prueban casos reales: qué pasa si el token expiró, qué
> pasa si mandas una posición GPS inválida (latitud 999), qué pasa si el servicio de gRPC no
> responde. Para simular fallas de red sin depender de infraestructura real, uso servidores gRPC
> "in-process" (de prueba, en memoria) que simulan tanto el caso exitoso como el de error.

---

## 7. Preguntas trampa / de arquitectura general

**"¿Por qué microservicios y no un solo programa (monolito)?"**

> Porque las partes del sistema tienen necesidades muy distintas: `realtime-service` necesita
> escalar mucho durante picos (muchas salas activas mandando GPS a la vez), mientras que
> `auth-service` es de baja frecuencia pero alta sensibilidad (credenciales). En un monolito,
> ambos comparten el mismo ciclo de despliegue — un bug en el cálculo de ranking podría tumbar
> el login de todos. Separándolos, cada uno se despliega y escala independientemente.
>
> La contra es real: ahora hay más piezas que pueden fallar (si `auth-service` se cae,
> `realtime-service` lo nota), y hay que coordinar red entre servicios en vez de solo llamar un
> método. Por eso el gRPC tiene fallback — asumo que la comunicación entre servicios puede
> fallar, porque en un sistema distribuido eso es normal, no una excepción.

**"¿Dónde vive el estado de una sala? ¿Qué pasa si el servidor se reinicia?"**

> El estado *vivo* de una sala (quién está conectado, posiciones actuales) vive en memoria
> dentro de `realtime-service` — si el servicio se reinicia, esas salas activas se pierden. Es
> una decisión de diseño: las salas son sesiones efímeras de entrenamiento, no necesitan
> sobrevivir un reinicio del servidor. Lo que sí es persistente es el usuario (en Postgres) y el
> ranking calculado se cachea en Redis con expiración de 1 hora, para poder escalar
> `realtime-service` a varias instancias en el futuro sin que cada una tenga su propia versión
> del ranking.

**"¿Tiene balanceo de cargas? ¿Cómo funciona?"**

> Sí, en producción. El plan de Azure App Service corre con **2 instancias físicas** (workers) y
> el balanceador L7 integrado de la plataforma reparte las peticiones entrantes entre ellas — no
> hubo que provisionar un balanceador aparte. Cinco de los seis servicios (gateway, auth, room,
> session, metrics) corren balanceados en las 2 instancias, sin sesiones pegajosas, porque son
> *stateless*: todo su estado vive en PostgreSQL, Redis o RabbitMQ, así que cualquier instancia
> puede atender cualquier petición.
>
> La parte que más vale explicar es la excepción: `realtime-service` está **deliberadamente
> fijado a 1 instancia** (con *per-site scaling* del plan). Guarda el estado vivo de las salas en
> memoria — si corriera en 2 instancias, dos atletas de la misma sala podrían caer en máquinas
> distintas y no verse entre sí. Esto conecta con la pregunta anterior del estado: el balanceador
> expone exactamente la diferencia entre servicios stateless (escalan horizontal gratis) y
> stateful (hay que sacar el estado del proceso primero). El camino para balancearlo también está
> definido: mover el estado de salas a Redis y propagar las posiciones por RabbitMQ; con eso
> dejaría de ser stateful y escalaría como los demás.

> Buena respuesta honesta: room-service, session-service y metrics-service tienen toda la
> infraestructura (CI/CD, conexión a su base de datos) pero no tienen lógica de negocio
> implementada todavía — el foco de esta entrega fue el flujo completo de autenticación y
> tiempo real. El despliegue en producción ya está completo y verificado (los 6 servicios en
> Azure App Service + frontend en Azure Static Web Apps; ver `docs/architecture/DESPLIEGUE.md`);
> lo que sí queda pendiente del lado de infraestructura es el gRPC *entre* servicios en la nube:
> Azure App Service expone solo un puerto público por app, así que para que realtime-service
> resuelva nombres contra auth-service en producción haría falta una red privada (VNet). Hoy el
> código lo maneja con el fallback: si el gRPC no responde, usa el nombre que envió el cliente.

**"¿Cómo sabes que lo que está desplegado es la versión real y no una demo con datos falsos?"**
*(lección real de este proyecto — úsala a tu favor)*

> Me pasó de verdad y lo detecté probando: el primer despliegue del frontend mostraba salas y
> atletas "hardcodeados" (inventados en el código). La causa no fue el pipeline — el CI estaba
> verde — sino el flujo de ramas: la versión conectada al backend real se había fusionado a
> `develop`, pero nunca se promovió a `main`, y producción despliega desde `main`. O sea que el
> pipeline desplegaba, correctamente, código viejo.
>
> La corrección fue promover `develop` a `main` con un PR, y de paso eliminar la única sección
> que seguía siendo maqueta (la lista de "salas activas", porque el backend aún no tiene un
> endpoint para listar salas — preferí quitarla antes que mostrar datos falsos). Al pasar por el
> pipeline, SonarCloud detectó además una vulnerabilidad real en el código promovido (el código
> de sala y el token se insertaban en la URL del WebSocket sin validar) que corregí con
> validación de formato y encoding antes de poder fusionar.
>
> La moraleja que puedo defender: "CI verde" no garantiza que producción tenga el código que
> crees — hay que verificar el *contenido* desplegado (en este caso, probar el flujo real desde
> un celular), y el Quality Gate del pipeline demostró su valor bloqueando una vulnerabilidad
> justo cuando el código real iba camino a producción.

---

## 8. Glosario rápido (por si preguntan "¿qué es X?")

| Término | Explicación en una línea |
|---|---|
| **JWT** | Un token firmado que prueba que un usuario ya se autenticó, sin tener que consultar la base de datos en cada petición |
| **REST** | Estilo de comunicación HTTP con verbos (GET/POST) y rutas (`/auth/login`) — pregunta/respuesta simple |
| **WebSocket** | Una conexión que se queda abierta entre navegador y servidor, para mandar datos en ambas direcciones sin re-conectar |
| **gRPC** | Comunicación entre servidores usando un contrato estricto (`.proto`) y formato binario, más rápido que JSON |
| **API Gateway** | Un servidor que recibe todo el tráfico externo y lo reparte a los microservicios internos |
| **Microservicio** | Un programa pequeño con una sola responsabilidad, que se despliega independientemente de los demás |
| **CI/CD** | Pipeline automático que compila, prueba y valida el código en cada cambio antes de fusionarlo |
| **JaCoCo** | Herramienta que mide qué porcentaje de tu código realmente ejecutan los tests |
| **BCrypt** | Algoritmo para "hashear" contraseñas — las hace irreversibles antes de guardarlas |
| **Haversine** | Fórmula matemática para calcular distancia entre dos coordenadas GPS sobre la superficie de la Tierra |
| **Redis** | Base de datos en memoria, muy rápida, usada aquí para cachear el ranking calculado |
| **RabbitMQ** | Sistema de mensajería para comunicación asíncrona entre servicios (infraestructura lista, no consumida activamente aún) |
| **WebRTC** | Estándar del navegador para audio/video en tiempo real directo entre dos clientes (P2P), sin pasar por el servidor |
| **Señalización** | El intercambio previo entre dos peers WebRTC para acordar cómo conectarse (ofertas SDP + candidatos ICE); aquí viaja por el WebSocket de la sala |
| **STUN** | Servidor que le dice a cada navegador cuál es su dirección pública en internet, para que dos peers detrás de routers puedan encontrarse |

---

## 9. Si te preguntan algo que de verdad no sabes

Frase honesta que suena bien: **"Esa parte específica la implementé apoyándome en herramientas de asistencia de código, pero puedo explicar la lógica del flujo — [explicas el flujo con tus palabras usando este documento]"**. Lo que evalúan normalmente no es que memorices cada línea, sino que entiendas por qué el sistema está armado así y puedas razonar sobre los trade-offs. Ese es exactamente el contenido de este archivo.
