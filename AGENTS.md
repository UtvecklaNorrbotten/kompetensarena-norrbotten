<!-- LOVABLE:BEGIN -->
> [!IMPORTANT]
> This project is connected to [Lovable](https://lovable.dev). Avoid rewriting
> published git history — force pushing, or rebasing/amending/squashing commits
> that are already pushed — as it rewrites history on Lovable's side and the
> user will likely lose their project history.
>
> Commits you push to the connected branch sync back to Lovable and show up in
> the editor, so keep the branch in a working state.
<!-- LOVABLE:END -->

## Arkitekturregler
- Adminvyer ligger under `/admin/*`, är `ssr: false`, finns inte i navigation.ts och läser via serverfunktioner med `requireSupabaseAuth` + `has_role(admin)`; varför: ett enda behörighetssystem (user_roles) och inget adminläckage i publik SSR.
- Datakällestatus härleds generellt ur `data_source_runs` (via `source_id`) med `data_source_state` som reserv; varför: inga källspecifika villkor i UI när nya källor tillkommer.
