# Workflows desactivados (Kaos)

Workflows heredados de Moonfin que GitHub no ejecuta mientras estén en esta
carpeta (solo se ejecutan los de `.github/workflows/`).

| Workflow | Motivo |
|---|---|
| `auto-update-aur.yml` | Publica en el AUR de Moonfin al crear una release. |
| `winget.yml` | Publica en winget al crear una release. |
| `release-web-bundle.yml` | Sube el bundle web de Moonbase al crear una release. |
| `deploy-web-pages.yml` | Despliega la versión web en GitHub Pages en cada push a `main`. |
| `close-stale-issues.yml` | Cierra issues antiguas automáticamente. |
| `label-platform.yml` | Etiqueta issues y PRs según la plataforma. |
| `require-bug-evidence.yml` | Exige pruebas en los reportes de bugs. |

Para reactivar uno, muévelo de vuelta a `.github/workflows/`.
