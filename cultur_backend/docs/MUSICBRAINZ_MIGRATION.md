# Catálogo de música: Last.fm (fonte principal)

O Cultur usa **[Last.fm API](https://www.last.fm/api)** como fonte canónica para pesquisa, detalhe de álbuns, página de artista, home (popular / seguidos), import Musicboard e resolução de pendentes.

**MusicBrainz** e **Cover Art Archive** deixam de ser chamados no fluxo normal; um link opcional para MusicBrainz continua a aparecer quando o Last.fm devolve `mbid` no álbum ou artista.

**Fanart.tv** (opcional, `FANART_API_KEY`) usa o MBID do artista vindo do Last.fm para fotos.

## Configuração

| Variável | Obrigatório | Descrição |
|----------|-------------|-----------|
| `LASTFM_API_KEY` | Sim | [API account](https://www.last.fm/api/account/create) |
| `LASTFM_HOME_TAG` | Não | Tag para prateleira “popular” (default: `rock`) |
| `FANART_API_KEY` | Não | Fotos de artista |

Rebuild da API após alterar `.env`:

```bash
cd cultur_backend && docker compose up -d --build cultur-api
```

## IDs no Cultur

| Conceito | Formato |
|----------|---------|
| Álbum (media) | `source=lastfm`, `external_id=lfm-album:{stableKey}` |
| Artista (person) | `lfm-artist:{mbid}` ou `lfm-artist:n/{nome codificado}` |
| Legacy person | `mb-artist:` / `mb-artist-` ainda são aceites na API |

## Fluxo

```
Flutter → music_catalog_service → lastfm_client (+ fanart_client opcional)
```

Pesquisa (`/catalog/music?section=search`), detalhe de álbum, artista, home, edit/lookup, import e follow usam só Last.fm.
