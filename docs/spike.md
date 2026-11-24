# Spike : secrets, vars et environments entre repos d'un compte User

Date : 2026-11-24. Compte GitHub `barlito` de type User, plan Free.

## Montage

- Reusable temporaire `barlito/ci/.github/workflows/spike.yaml@spike/phase-1` (branche supprimée depuis) : un job sans `environment`, un job avec `environment: production`. Chacun affiche si `SPIKE_REPO_SECRET`, `SPIKE_REPO_VAR`, `SPIKE_ENV_SECRET`, `SPIKE_ENV_VAR` sont présents, et les clés de `toJSON(secrets)`.
- Deux callers identiques en `secrets: inherit`, `permissions: { contents: read, deployments: write }` :
  - `barlito/ci-spike-private` (privé), runs 45297549993 (branche `main`) et 45297782554 (`--ref v0.0.1`) ;
  - `barlito/ci-spike-public` (public), run 45297557750.
- Chaque caller porte une variable et un secret de repo, et un environment `production` avec sa variable et son secret.

## Résultats

| Question | Privé | Public |
|---|---|---|
| (a) `secrets: inherit` entre repos d'un compte User | OK | OK |
| (b) `vars` du caller visibles dans le reusable | OK | OK |
| (c) secrets et vars d'environment lus par un job de reusable avec `environment:` | OK | OK |
| (d) appel du reusable public | OK | OK |
| Deployment GitHub créé automatiquement | OK | OK |

Constats complémentaires :

- Les secrets et vars d'environment n'existent que dans le job qui déclare `environment:`. Sans environment, seuls les secrets et vars de repo sont visibles.
- `toJSON(secrets)` fonctionne sous `inherit` et liste aussi `github_token` (en minuscules). L'allowlist `env-secrets` doit n'exporter que les noms listés.
- `github.repository`, `github.ref` et `github.workflow_ref` sont ceux du caller (`workflow_ref` pointe le workflow caller, pas celui de `barlito/ci`).
- Le Deployment porte `environment: production`, `task: deploy`, la ref du dispatch (`v0.0.1` pour un dispatch `--ref v0.0.1`) et le sha du caller.
- L'environment fonctionne sur le repo privé alors que le compte est en Free (la documentation GitHub le réserve à Pro).
- `gh run view --log` renvoie un log vide quand les jobs viennent d'un reusable : lire `gh api repos/<repo>/actions/jobs/<id>/logs`.

## Conclusion

Aucun repli nécessaire : `secrets: inherit` avec allowlist d'export (D7) et un GitHub Environment par serveur cible (D8) tiennent pour tous les repos, privés comme publics. Le repli prévu (secrets explicites + secret dotenv `DEPLOY_ENV`) est abandonné.
