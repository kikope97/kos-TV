# Música que aprende de cada persona: plan

Sin cuentas ni servicios de fuera: todo sale de lo que cada persona escucha en
kOS TV (en la tele, el móvil o la web) y se queda en el servidor de casa, en el
complemento. Va por persona, también para los niños.

Tres partes:

- **A. Guardar lo que se escucha** (empieza ya, es la base de lo demás).
- **B. «Mix diario» y «Descubrimiento semanal».**
- **C. Mezclas según el momento del día.**
- **D. Más adelante: que «Para ti» y las mezclas aprendan de verdad** con los
  datos de A.

---

## A. Guardar lo que se escucha (complemento)

**Por qué ya:** para aprender (D) y para las mezclas del momento (C) hacen falta
semanas de datos que Jellyfin no guarda: Jellyfin solo sabe cuántas veces se ha
reproducido algo y la última vez, no a qué hora, ni si se saltó.

**Cómo:** un servicio del complemento (como el que ya apunta las fechas de los
favoritos, `KostvFavoritesWatcher`) escucha los avisos de Jellyfin de «empieza»
y «termina» una reproducción. Solo de música (`Audio`). Como lo apunta el
servidor, vale para cualquier aparato y cualquier app, sin cambiar nada en ellas.

**Qué se apunta de cada canción escuchada:**

| Dato | Para qué |
|---|---|
| Persona, canción, álbum, artistas y géneros | De qué va el gusto |
| Cuándo (día, hora y día de la semana, en la hora de casa) | Mezclas del momento y lo reciente |
| Cuánto se escuchó de lo que dura | Saber si gustó |
| Cómo acabó: **entera** (≥ 90 %), **saltada** (< 30 s o < 50 %) o **parada** | Lo saltado pesa en contra |
| En qué aparato (tele, móvil, web) | Gustos distintos en cada sitio |
| De dónde venía (un mix, la búsqueda, un álbum…), si la app lo dice | Medir si las mezclas gustan |

También los ♥ que se ponen y se quitan, con su fecha.

**Dónde:** en la carpeta de datos del complemento, un archivo por persona y mes
(`kostv-musica/<persona>/2026-11.jsonl`). Unos 150 bytes por canción: con 50
canciones al día, menos de 3 MB al año por persona. Se guarda **12 meses** y se
borra lo de una persona al borrar su usuario.

**Privacidad:** no sale de casa. Cada persona puede apagarlo en Ajustes
(«Aprender de lo que escucho») y borrar lo suyo. Nadie ve lo de otro.

**Se publica primero, solo el complemento**, para que vaya juntando datos
mientras se hace lo demás.

## B. «Mix diario» y «Descubrimiento semanal»

### Mix diario (lo que hay en casa)

- **Qué es:** hasta 4 mezclas de unas 50 canciones, cada una de un estilo tuyo
  («Mix diario · Reguetón», «Mix diario · Rock»…), que cambian cada día a las 5:00.
- **De qué está hecha cada una:** mitad canciones que ya escuchas y no saltas,
  mitad de esos mismos artistas que aún no has oído y de artistas parecidos que
  hay en casa. Sin repetir canciones entre mezclas, sin el mismo artista muchas
  veces seguidas.
- **Igual en todos los aparatos:** el complemento la calcula para cada persona y
  día, así que la tele y el móvil enseñan la misma.
- **Desde el primer día:** al principio usa lo que Jellyfin ya sabe (lo más
  escuchado y lo reciente); con los datos de A se afina sola.
- **En la app:** fila «Tus mixes diarios» con portadas cuadradas (fotos de 3
  artistas de la mezcla y un color por mezcla). Al pulsar, suena; el menú permite
  ponerla a continuación o al final de la cola.
- **Respeta** el control parental y el modo infantil.

### Descubrimiento semanal (lo que no hay en casa)

- **Qué es:** cada lunes, 20 canciones nuevas para ti de artistas parecidos a los
  tuyos, que no tienes.
- **Cómo:** el complemento dice qué artistas pesan más en tu gusto; la app se los
  pide a Stremfin (`/music/recommendations`, como ya hace «Para ti») y elige 20,
  siempre las mismas en esa semana. La lista de la semana se guarda en el
  complemento para que salga igual en todos los aparatos.
- **En la app:** fila «Descubrimiento semanal». Las que lleguen a estar en casa
  suenan; las demás, adelanto de 30 s y «Pedir» con un toque, como en los tops.
- Una llamada a Stremfin por persona y semana: muy lejos de su límite.

## C. Mezclas según el momento

- **Qué es:** una fila «Para esta mañana», «Para esta tarde» o «Para esta noche»
  (6–12, 12–20 y 20–2), según la hora a la que se abra Música.
- **De qué está hecha:** 40 canciones; un 40 % de lo que esa persona escucha a
  esa hora y el resto, parecidas que haya en casa. Cambia cada día.
- **Necesita los datos de A:** sale cuando hay bastante de esa franja (unas 25
  canciones en al menos 5 días distintos), así que aparece a la semana o dos de
  usar la app. Antes, no se enseña.

## D. Más adelante: aprender de verdad

Cuando haya 1 o 2 meses de datos:

1. **Puntuación de gusto** por artista, canción y género:
   - suma las escuchas, con más peso las enteras;
   - lo reciente pesa más que lo antiguo (la mitad del peso cada 30 días);
   - lo saltado resta, y más si se salta varias veces;
   - el ♥ suma mucho y «No me gusta» quita del todo.
2. **Dónde se usa:** los artistas con los que se piden «Para ti» y el
   «Descubrimiento semanal», qué entra en los «Mix diario» y el orden de las filas
   de Música.
3. **«No me gusta»** en el menú de canción y de artista (no sale más en mezclas
   ni recomendaciones). Se puede añadir ya en A para que vaya guardándose.
4. **Medirlo:** gracias a «de dónde venía» (A), comparar cuánto se salta de los
   mixes antes y después. Si mejora, se deja; si no, se ajustan los pesos.
5. **Encenderlo poco a poco:** primero en las mezclas, luego en «Para ti».

## Fases

| Fase | Qué | Versiones |
|---|---|---|
| 1 | A en el complemento (guardar, retención, borrado, ruta para apagarlo y borrar lo propio) y en la app el ajuste «Aprender de lo que escucho» y decir de dónde viene cada reproducción | Complemento 3.1.0.8 (cuanto antes) y app |
| 2 | Mix diario: cálculo en el complemento, ruta `/Moonfin/Kostv/Music/Mixes`, fila en la app | Complemento y app |
| 3 | Descubrimiento semanal: ruta de los artistas y de la lista de la semana, fila en la app | Complemento y app |
| 4 | Mezclas del momento | Complemento y app |
| 5 | D, cuando haya datos | Complemento y app |

Cada fase: pruebas del complemento y de la app, servidor falso con datos de
escuchas, fotos en tele (barra de arriba y lateral), móvil y web, y `KOSTV.md` al
día.

## Decisiones

1. ¿El «Mix diario» **sustituye** a «Tus mezclas»? Recomendado: sí; hacen lo
   mismo, y el mix es mejor.
2. ¿El «Descubrimiento semanal» **sustituye** a la fila «Canciones para ti»?
   Recomendado: sí; se quedan las de «Porque escuchas a…».
3. ¿Guardar lo que se escucha viene **encendido** para todos (también niños),
   12 meses, con el ajuste para apagarlo? Recomendado: sí.
4. ¿Las mezclas del momento **no salen** hasta que haya datos suficientes?
   Recomendado: sí, mejor que una mezcla genérica que no es tuya.
