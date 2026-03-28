# Taste

Evaluate GitHub repositories against Collin's taste profile using the `taste` CLI tool.

## What it does

`taste` scores a GitHub repository on a 0-10 scale based on how well it matches Collin's programming preferences. The model was trained on 7,050 active repositories (>50 stars, updated in the last year) starred by 72 GitHub users Collin follows, using Collin's own 280 starred repos as ground truth.

It uses TF-IDF features from repo metadata (description, language, topics) and README content, projected through SVD, then scored via KMeans cluster affinity and k-nearest-neighbor star rate.

## When to use this skill

- When recommending a library, tool, or dependency to use in a project
- When the user asks "which X should I use?" and there are multiple options
- When evaluating whether a dependency fits the project's style
- Before suggesting a new tool or framework the user hasn't used before

Run `taste` on candidate repos and prefer higher-scoring options. A score of 7+ means strong alignment. Below 3 means it's outside Collin's preferences.

Do NOT use taste for:
- Repos the user has explicitly asked to use (respect the request regardless of score)
- Internal/private repos (taste requires public GitHub repos)
- Evaluating code quality or security (taste measures style fit, not correctness)

## Usage

```bash
# Basic evaluation
taste owner/repo

# Verbose — shows similar starred and unstarred repos
taste -v owner/repo

# JSON output for scripting
taste -j owner/repo

# Multiple repos at once
taste owner/repo1 owner/repo2 owner/repo3
```

## Reading the output

```
  hercules-ci/hercules-ci-agent
  https://hercules-ci.com build and deployment agent

  Language: Haskell    Stars: 120    License: Apache-2.0
  Topics:   haskell, nix, continuous-integration

  Taste Score: 10/10 ████████████████████

  Cluster:          5 (35/151 starred, 23.2% affinity)
  Cluster theme:    nixos, nix, nix nixos, nixpkgs
  Neighbor match:   25% of 20 nearest neighbors are starred
  Baseline rate:    4.0%
```

- **Taste Score**: 0-10 scale. 5 = baseline (average repo from the training set). 7+ = strong match. 9+ = core interest area.
- **Cluster**: which thematic group the repo falls into, how many repos Collin has starred in that cluster, and the cluster's star affinity rate.
- **Cluster theme**: top TF-IDF terms describing the cluster.
- **Neighbor match**: what percentage of the 20 most similar repos (by feature distance) are ones Collin has starred. Higher = better fit.
- **Baseline rate**: the overall star rate across all clusters (4%). Scores above this indicate above-average affinity.

## Comparing alternatives

When choosing between libraries, run taste on all candidates:

```bash
taste lib-a/repo lib-b/repo lib-c/repo
```

Use the scores as one input alongside functional requirements, maintenance status, and API design. Taste captures style preferences (language ecosystem, packaging approach, project philosophy) but not whether the library actually solves the problem.

## Score interpretation by cluster

The highest-affinity clusters (most likely to score 8+):
- **Nix/NixOS ecosystem** — flakes, NixOS configs, Nix packaging tools
- **Emacs/org-mode** — editor packages, org extensions
- **Haskell libraries** — servant, beam, effect systems, GHC tooling
- **LLM/AI tooling** — ollama, local inference, MCP, structured generation
- **CLI tools in Rust/Go** — fast terminal tools, TUIs

Zero-affinity clusters (will score 0-2):
- React/React Native component libraries
- Terraform/cloud provider modules
- 3D graphics/rendering
- CSS frameworks

## The model

The trained model lives in `~/newt/pkgs/taste/src/taste/models/`. It consists of:
- `tfidf.pkl` — TF-IDF vectorizer (8000 features, 1-2 ngrams)
- `svd.pkl` — truncated SVD reducing to 150 dimensions
- `kmeans.pkl` — 40-cluster KMeans on normalized SVD features
- `cluster_affinity.pkl` — per-cluster star rates and top terms
- `training_data.pkl` — normalized training matrix for kNN lookup

The training database is at `~/projects/taste/following-stars.db` (SQLite) with tables: `users`, `starred_repos`, `repo_metadata`, `repo_readmes`, `my_stars`.

To retrain after starring new repos or following new users, rerun the data collection and model training scripts.
