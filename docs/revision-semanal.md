# Revisión semanal del proyecto principal y del complemento

Cada semana se mira qué ha cambiado en:

- **La app de la que partimos:** Moonfin-Core (`upstream` en git,
  `https://github.com/Moonfin-Client/Moonfin-Core`, rama `main`). Se busca lo
  que merece la pena traer a kOS TV: arreglos del reproductor, fallos,
  rendimiento, seguridad y mejoras que encajen con la familia.
- **El complemento del servidor:** Moonbase, el oficial
  (`https://github.com/Moonfin-Client/Plugin`, versiones en su
  [`manifest.json`](https://raw.githubusercontent.com/Moonfin-Client/Plugin/refs/heads/master/manifest.json)).
  Con especial cuidado: qué ha cambiado, qué hay nuevo que aprovechar y qué
  podría romper la app (las rutas `/Moonfin/...` que usa). Se decide si
  actualizarlo en el servidor o esperar.

Cómo se hace y cuándo se pregunta: ver la norma en [`CLAUDE.md`](../CLAUDE.md).

**Cada revisión se apunta aquí, siempre**, aunque no se integre nada o el
usuario decida dejarla para otro día (entonces se apunta que se pospuso). Es el
historial de dónde venimos y de lo que se ha ido haciendo: no se borra ni se
reescribe lo anterior, solo se añade arriba.

## Dónde estamos ahora

Se actualiza al terminar cada revisión. La siguiente empieza justo aquí.

| | |
|---|---|
| Copia original de kOS TV | upstream `3d87996d2` (2026-11-10) |
| Último commit de upstream revisado | ninguno todavía (se parte de `3d87996d2`) |
| Última versión del complemento revisada | 3.0.0.0 (2026-10-30), solo vista, sin revisión a fondo |
| Complemento instalado en el servidor de casa | ninguno todavía (se instalará el oficial) |
| Última revisión | ninguna todavía |

## Cómo apuntar cada revisión

Copiar este bloque arriba del registro y rellenarlo:

```
### AAAA-MM-DD

- **App, revisado:** upstream `<desde>`..`<hasta>` (N commits, fechas).
- **Integrado:** qué se trajo y con qué commit nuestro (o «nada»).
- **Descartado:** qué no aplica y por qué (Plex, Emby, Silo, escritorio,
  Seerr, Firebase, ya lo teníamos…).
- **Dudoso o pendiente:** lo que el usuario decide más adelante.
- **Complemento, revisado:** versiones `<desde>` → `<hasta>`; qué cambia en
  las rutas `/Moonfin/...` que usa la app; qué hay nuevo; si rompe algo.
- **Decisión del complemento:** actualizar en el servidor, esperar o volver
  atrás (y por qué). Versión instalada en el servidor después.
- **Notas:** cualquier otra cosa que convenga recordar.
```

## Registro

### 2026-11-11 · Punto de partida (sin revisión todavía)

- **App:** la copia de kOS TV sale de upstream `3d87996d2` (2026-11-10). En
  upstream `main` hay 23 commits nuevos desde entonces, hasta `d31a38f8b`
  (2026-11-11), sin revisar.
- **Desde la copia, kOS TV ha cambiado mucho** (ver la tabla de `KOSTV.md`):
  marca propia, sin Plex, Emby, escritorio, Seerr ni Firebase, servidor de casa
  integrado, Descubrir (Stremfin), web en Docker, aplicaciones de la tele,
  intro en vídeo… Todo lo que venga de upstream se mira teniendo eso en
  cuenta.
- **Complemento:** el oficial va por la 3.0.0.0 (2026-10-30, Jellyfin 10.10 o
  superior), que es la 2.5.0 renumerada para ir con las apps Moonfin 3.0.0.
  Aún no está instalado en el servidor de casa; se decidió usar el oficial y
  no una copia propia (que lo mantengan ellos; si un día rompe algo, se vuelve
  a una versión anterior o se copia y lo seguimos nosotros).
