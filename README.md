# Parcial 2 - Programación 3
**Universidad del Quindío**  
**Facultad de Ingeniería - Programa de Ingeniería de Sistemas y Computación**  
**Estudiante:** José Daniel Carmona  

---

## 1. Organización del Repositorio

El repositorio se encuentra estructurado en carpetas independientes para cada punto evaluado, respetando la disposición de recursos solicitada:

```text
parcial-2-elixir/
├── README.md
├── LICENSE
├── punto-1/
│   ├── main.exs
│   └── resources/
│       ├── ciudades.txt
│       ├── movimientos.txt
│       └── reporte_sismos.txt
└── punto-2/
    ├── nodo-cliente/
    │   └── cliente.exs
    └── nodo-servidor/
        ├── servidor.exs
        └── resources/
            ├── ciudades.txt
            └── movimientos.txt
```

---

## 2. Instrucciones de Ejecución

### Punto 1: Reporte Local

1. Abrir la terminal y ubicarse en la carpeta del Punto 1:
   ```bash
   cd punto-1
   ```
2. Ejecutar el script principal:
   ```bash
   elixir main.exs
   ```
3. **Ubicación de archivos y resultados:**
   - **Archivos de entrada:** `punto-1/resources/ciudades.txt` y `punto-1/resources/movimientos.txt`.
   - **Reporte generado:** `punto-1/resources/reporte_sismos.txt`. Cada ejecución exitosa actualiza dicho archivo con la versión consolidada del reporte mostrado en consola.

---

### Punto 2: Consulta de Reportes Sísmicos entre Nodos

La arquitectura distribuida requiere dos terminales independientes comunicadas a través de nombres de nodo (`--sname`) y una clave compartida (`--cookie`).

* **Cookie compartida:** `sismos_secret`
* **Nombre de nodo servidor:** `servidor`
* **Nombre de nodo cliente:** `cliente`

#### Paso 1: Iniciar el Nodo Servidor (Terminal 1)
```bash
cd punto-2/nodo-servidor
elixir --sname servidor --cookie sismos_secret servidor.exs
```
El servidor registrará localmente el proceso como `:servicio_sismos` y quedará a la espera de solicitudes.

#### Paso 2: Iniciar el Nodo Cliente (Terminal 2)
```bash
cd punto-2/nodo-cliente
elixir --sname cliente --cookie sismos_secret cliente.exs servidor@localhost
```
*(Nota: En sistemas operativos o entornos de red específicos, reemplace `servidor@localhost` por el identificador exacto mostrado por el servidor, por ejemplo `servidor@DESKTOP-L6A2QRB`).*

---

## 3. Verificación del Punto 2

### Identificadores utilizados para las pruebas
El cliente envía de manera automática y secuencial las siguientes consultas obligatorias:
1. **Ciudad con movimientos registrados:** `C01` (Armenia, con 2 movimientos asociados, mayor magnitud $3.4$ en $S001$ y profundidad promedio $14.00\text{ km}$).
2. **Ciudad sin movimientos registrados:** `C03` (Circasia, responde con «Sin movimientos registrados», total $0$ y «No aplica» en magnitud máxima y promedio).
3. **Ciudad inexistente:** `C99` (El servidor responde puntualmente con `La ciudad no está registrada`).
4. **Reporte general:** Consolidado de todas las ciudades válidas y estadísticas de registros rechazados por archivo.
5. **Cierre de protocolo:** Envío del mensaje `:fin` y recepción de la confirmación correspondiente.

### Prueba de persistencia del servidor (Segunda ejecución consecutiva)
Para comprobar que el servidor mantiene su ciclo de atención activo y no finaliza tras despachar a un cliente:
1. Mantenga la **Terminal 1 (Servidor)** en ejecución sin interrumpirla.
2. En la **Terminal 2 (Cliente)**, vuelva a ejecutar el comando por segunda vez:
   ```bash
   elixir --sname cliente --cookie sismos_secret cliente.exs servidor@localhost
   ```
3. El cliente recibirá nuevamente las 4 respuestas en el orden indicado y cerrará con `:fin`, evidenciando el bucle recursivo del proceso servidor.

---

## 4. Reflexión sobre el uso de Inteligencia Artificial

1. **Herramientas y agentes:**  
   Se utilizó el modelo Gemini 3.8 Flash como asistente técnico enfocado en la estructuración de la concurrencia distribuida, la compatibilidad de lectura de archivos en entornos Windows (retornos `\r\n`) y la implementación de recursividad para el procesamiento de estadísticas sin emplear funciones de orden superior de `Enum`.

2. **Caso decisivo:**  
   Durante la implementación del acumulador de estadísticas por ciudad, se requería calcular en un único recorrido la cantidad total, el sismo de mayor magnitud (conservando el primero en caso de empate) y la sumatoria de profundidades para el promedio. La interacción permitió diseñar una función recursiva con acumulador que cumple estrictamente esta condición en tiempo $O(n)$, contrastando los resultados directamente contra el caso testigo de Armenia ($14.00\text{ km}$ de profundidad promedio).

3. **Idea diferente de la clase:**  
   El uso del esquema de direccionamiento desacoplado `{ {:servicio_respuesta, node()}, solicitud }` junto con la verificación dinámica y desregistro previo (`Process.whereis` / `Process.unregister`) en el nodo cliente. Esto garantizó que ejecuciones consecutivas o sesiones en entornos interactivos no quedaran bloqueadas por PIDs huérfanos asociados al átomo `:servicio_respuesta`.

4. **Conclusiones:**  
   Se consolidó la comprensión práctica del modelo de actores, el paso de mensajes asíncrono con `spawn`/`send`/`receive`, y la interconexión de nodos distribuidos en la máquina virtual BEAM. Como oportunidad de mejora para proyectos futuros, se destaca la importancia de homogeneizar las rutas relativas mediante `__DIR__` desde el inicio para evitar desajustes causados por el directorio de trabajo del sistema operativo.
