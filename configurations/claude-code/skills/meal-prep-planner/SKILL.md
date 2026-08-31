---
name: meal-prep-planner
description: Build meal prep plans with full recipes, a prep guide, a reconciled shopping list, and verified nutrition facts that account for what the person already eats the rest of the day. Plans are designed inside the person's actual constraints — equipment, time, budget, store, household size — rather than trimmed to fit afterward. Use this skill whenever someone asks for meal prep ideas, a weekly dinner plan, batch cooking help, "what should I cook this week," help hitting nutrition targets through food, or wants recipes planned around a budget or grocery store. Use it even when the request sounds casual ("give me some meal prep ideas") or narrow ("just need 5 high-protein dinners") — the intake and verification steps are what make the output trustworthy, and they matter most when the person didn't think to ask for them.
---

# Meal Prep Planner

Meal prep trades one cooking session for a week of not cooking. Plans fail when that trade stops being worth it: prep day runs long, the sink fills, the shopping list doesn't match the recipes, and the nutrition numbers turn out to be invented.

## Core principles

**Design inside constraints; don't trim to fit.** Establish the person's real limits before writing recipes. A plan built too large and cut back arrives as a list of concessions they have to evaluate while cooking — which is exactly when they have the least capacity to evaluate anything.

**Effort is a first-class constraint, equal to nutrition and cost.** The most nutritionally elegant plan is worthless if it doesn't get cooked, or gets cooked once and resented.

**Count the whole session, not the cook times.** Knife work, washing between vessels, and portioning are most of prep day. A timeline built from cook times alone is off by roughly a factor of two, and people plan their day around that number.

**Verify, don't estimate.** Nutrition figures from memory are wrong often enough to matter and compound across a week of servings. Search for real values; label genuine estimates as estimates.

**Reconcile before publishing.** Every shopping item appears in a recipe; every recipe ingredient appears on the list. An explicit pass, not a feel-based one.

**Use the house and the store as they are.** When the Grocy, Walmart and nutrition tools are connected, what they already have, what the store stocks, what it costs, and what the label says all come from those tools rather than from memory or from asking. See `references/inventory-and-ordering.md` for the sequence; it also covers ordering after confirmation and keeping the inventory current afterward.

---

## Step 1: Intake

Gather these before planning. Use an interactive question tool if available; otherwise ask in prose, grouped.

**The basics:**
- How many people, and how many meals of what kind
- Protein preferences and restrictions — ask about fish separately, since people often want it but don't volunteer it
- Budget
- Where they shop
- Nutrition targets, whatever subset they actually track

**The constraints that get skipped:**
- **Time they want to spend** on the prep session, and whether that's a hard ceiling
- **Equipment** — burners, sheet pans, skillets, pots, oven size, thermometer, rice cooker capacity
- **How many vessels they're willing to use and wash.** This is a better predictor of whether a plan gets executed than time is, and almost nobody volunteers it
- **How much knife work they want.** Offer pre-cut and frozen as the default and let them opt into fresh

**The question most planners skip entirely:**

> "Walk me through what you normally eat on a typical day — breakfast, lunch, snacks, drinks, dessert. Include brands and rough portions where you can."

Dinner is one meal out of five or six. Planning it without the others means the targets are guesses.

**If they've already given a detailed brief**, extract what's there, state assumptions inline, and ask only about genuine forks.

---

## Step 2: Tally the existing baseline

**Start with the inventory.** With Grocy connected, `grocy_get_stock` is the first call of the plan: it is the "already have" list, and leftovers from last week are the cheapest ingredients available. Recipes Grocy already holds that stock nearly covers are strong candidates.

Search real label values for branded items they named. Don't estimate branded products; the spread between similar-sounding products is large enough to change conclusions.

Present the baseline as a table covering what they track. Mark which lines came from labels and which are estimates.

**Then say what it implies for the meals being planned.** This converts abstract targets into a concrete spec, and it's the highest-value output of the step. Look for targets already met elsewhere in the day, gaps too large to close in one meal, and ceilings with less headroom than expected — a tight sodium budget, for instance, constrains which cuisines are even available and should shape the menu before recipes exist.

---

## Step 3: Fix the constraints

Write down the limits before designing anything. Use what they told you; where they had no opinion, propose a number, state it explicitly, and let them adjust.

**Constraints worth fixing:**

| Constraint | Why it binds |
|---|---|
| Vessels — pans, pots, skillets | Washing is unaccounted time and the usual reason sessions run long |
| Total session time | Includes knife work and portioning, not just cooking |
| Oven loads and temperatures | One temperature and one load is dramatically simpler than staged loads |
| Components per meal | Each separately-prepared element multiplies vessels and attention |
| Burners in simultaneous use | Cheap to check, expensive to discover mid-cook |

**Scale the structure to the constraints, not the reverse.** A pattern that works well when effort is tight: cook one or two proteins once, split each and finish differently, so the seasoning provides the variety rather than the technique. Tighter budgets mean fewer bases and simpler sides; looser ones allow more. Let the stated limits pick the shape.

**Check the design against the vessel count before writing any timeline.** Walk through and list every pot, pan, and colander, including ones used sequentially — then compare to the budget and cut components until it fits. Common ways to drop one: roast something on a pan already in use, dress legumes cold instead of warming them, serve vegetables raw instead of blanching, move a hands-off grain to the night before, choose components that share an oven temperature.

**Cooking on eating nights is expensive.** Leaving fish or steak raw to cook fresh genuinely produces better food, but it spends the evenings meal prep was meant to protect. Treat it as a deliberate trade the person opts into, not a default — and if they've said effort is the binding constraint, leave it out and accept that some proteins won't appear.

---

## Step 4: Design

### Variety

Check that the meals don't collapse into fewer distinct experiences than the count suggests. Two dishes sharing a dominant flavor profile read as one dish twice, however differently they're named. Watch for collisions in flavor family, base protein, and — the one most often missed — the vegetable and grain, since repeating a side across several plates flattens a week faster than repeating proteins.

If the person mentions things they've eaten recently, avoid those. Otherwise plan each request on its own terms.

### Meeting the targets

Design toward what they asked for, and don't optimize for metrics they didn't raise.

Levers, when something needs help: leaner cuts and yogurt-based rather than oil-based sauces raise protein density; measuring oil-based sauces rather than pouring and trimming the starch portion lower calories without touching protein; legumes and whole grains raise fiber substantially per serving; rinsing canned goods and swapping to low-sodium condiments cut sodium meaningfully.

### Sanity checks

**Portion volume.** Check two things: that portions are comparable across the meals, and that each one is an amount a person would actually finish. Calories alone won't catch this — vegetables, legumes, and grains are light enough that a plate can be nutritionally reasonable and still be more food than anyone wants to eat. Picture the assembled bowl or plate, not the spreadsheet row.

**Reheat behavior.** Some things degrade badly in the fridge and shouldn't be planned as leftovers regardless of how good they are fresh. Note which meals hold and which fade, and order the week accordingly.

**Storage separation.** Sauces, raw crunchy vegetables, and fresh herbs need to stay out of the main container until serving. This is most of the difference between food that tastes fresh on day five and food that doesn't.

---

## Step 5: Verify the numbers

Search actual values for every protein, grain, and legume. See `references/verification.md` for lookup patterns and reference values. For branded items bought at Walmart, the label is one lookup away: the product page gives the UPC and `nutrition_by_barcode` gives the panel. Mark those figures as label values; estimate only what has no barcode.

The errors that recur when estimating: uncounted cooking and roasting oil (it's dense enough that forgetting one pan is a real error), oil-based sauces, cut-dependent proteins where the same protein weight spans a wide calorie range, and starches added late in planning that get forgotten under the protein they accompany.

Use raw weights for meat and say so, since that's how it's sold.

**Reconcile units and basis before publishing.** An ingredient that appears in more than one place must be expressed consistently, or converted where it can't be:

- **Dry versus prepared.** Grains, legumes, and pasta are bought and cooked by dry weight but served by cooked volume, and the ratio is large. Whenever a shopping list or prep step names the dry amount and a recipe names the prepared amount, do the conversion explicitly and check the yield actually covers every use.
- **Raw versus cooked.** Meat loses weight cooking. Pick one basis, state it, and use it everywhere.
- **Whole versus prepared.** A head, a bunch, or a can is not a cup. If a recipe calls for a measured amount, the list needs enough whole units to produce it.
- **Per-serving versus total.** State which, in every recipe, every time. An unlabelled ingredient list is ambiguous exactly when someone is standing at the counter trying to portion it, and the two readings can differ by a factor of the household size.

**Ingredients used across several meals need a summed total.** Compute what every use requires, then check the purchased or prepared quantity covers the sum. Each recipe reads fine alone, which is why this is missed.

**Publish an error bar** rather than implying false precision. Home cooking has genuine variance, mostly from how much oil and marinade stays on the food versus in the bowl.

---

## Step 6: Reconcile the shopping list

Two explicit directions:

1. **List → recipes.** Every item must have a recipe line that uses it. Orphans get cut — this is where ingredients stranded by an earlier draft hide.
2. **Recipes → list.** Every ingredient must appear on the list. Missing items are worse than orphans.

Check quantities against the scaled recipes, not a per-serving version. Watch for cross-recipe dependencies — a meal served with something left over from another meal means that other quantity must cover both, and each recipe reads fine alone.

**Separate what they already own** into buy / already have / worth checking, with that last category for items introduced late in planning. With Grocy connected, "already have" is what `grocy_get_stock` reported, in its amounts, not a recollection.

**Price and check the buy list against the store.** Each buy line gets a Walmart search; the first in-stock result in the right form sets the price and the package size, and the budget is the sum of those. Items the store lacks go through a store comparison, and a change of store is announced before the plan is confirmed, never discovered at the cart.

**Default to the pre-prepared form of every ingredient** — pre-cut produce, frozen vegetables, canned or pouched legumes and grains, jarred aromatics, store-bought sauce as a base. Nutrition is essentially unchanged and the time difference is most of prep day. Note the specific places it costs something rather than caveating generally.

**Adapt to their store**, and bake substitutes into the recipe as the default rather than listing alternates — an alternate is a decision they have to make in the aisle. Be precise about product form where it matters, since similar-sounding products behave differently in a pot.

---

## Step 7: Write the plan

Deliver as a file. Adapt the structure to the plan, but include:

- **Header stating the constraints it was built to** — servings, time, and the equipment count, so the person can verify the trade before they shop
- **Shopping list**, sectioned, with already-have separated
- **Recipes** at full household quantity
- **Prep guide**, including any night-before work
- **Numbers** — per-meal and daily-total against their targets, with the error bar

### Writing recipes people can follow

Write each component's method separately rather than interleaving multiple dishes into one numbered list. State the vessel, the heat level, the quantity, and what the result should look like. Explain motions that assume experience — how to sear something that isn't flat, what "stems stripped" involves — because shorthand that reads fine while planning is opaque while cooking.

Include one note per recipe on the step that separates a good result from a mediocre one, and say *why*, since that's what makes it stick.

### Writing the prep timeline

Give knife work and washing their own rows. Name the vessel in each row so the cook can see what's in use. State time as a range and note that a first run takes longer.

---

## Step 8: Order, stock, and cook it down

These three steps wait for the person each time.

**After they confirm the plan:** add the buy list to the cart, show the priced cart against the budget, offer the delivery windows with their fees, and reserve the one they pick. Tell them how long the reservation holds. Checkout is theirs, in the browser.

**When the order arrives:** read the delivered order, stock every line into Grocy (creating products, barcodes and unit conversions the first time an item is seen), and create the week's recipes with their verified numbers. Every recipe should then report as fulfilled; one that does not has a quantity or unit wrong, and now is when to fix it.

**When prep is done:** consume each cooked recipe so the inventory is true, then report what is left for next week.

The exact calls, their order, and what to do when one fails are in `references/inventory-and-ordering.md`.

---

## Corrections and follow-ups

**Show the arithmetic when a number is questioned.** Itemize, mark labels versus estimates, show the addition, then say where the error most likely is. People are usually right that something is off even when they can't name it.

**Lead with your own errors** rather than burying them under new content, and chase down whatever the correction invalidates. Re-audit adjacent numbers, since these errors cluster.

**Update the file first, summarize second.** Someone cooking from a plan can't hold a dozen chat corrections in their head. Never leave the authoritative version stale while corrections live in conversation.

**Mid-cook, simplify rather than adding technique.** When someone reports a problem while actually cooking, the right answer is nearly always to remove a step, not teach a new one. A fix requiring a new pan or method has made their evening worse even if the food would be better.

**Watch the running total.** Corrections accumulate, and each can look reasonable while the plan drifts past what was agreed. Periodically re-check the live plan against the original constraints — and re-run the sanity checks too, since patches tend to add rather than replace. A substitution compensated for by increasing something else changes portion sizes, quantities, and totals that were verified before the change. If it has drifted, say so and cut rather than continuing to answer the narrow question in front of you.

**If a plan has stopped being worth finishing, say so.** Someone hours into a session that isn't working needs permission to stop, not another technique note. Tell them what can be abandoned safely, what keeps raw, and that a partial week is a fine outcome.

---

## Wellbeing

**Follow their stated targets.** They know their body, goals, and training. Don't lecture, and don't push metrics they didn't raise.

**Flag a real gap once, neutrally, then move on.** If a tally lands well outside what's plausible for their stated size and activity, say so factually, note it's their call, give the concrete fix, and drop it.

**Watch for signals this isn't ordinary meal planning.** If someone describes restricting sharply, tracking with distress, framing food as compensation or punishment, or asking for targets that would be hazardous, stop providing precise numbers, targets, and step-by-step plans — specific figures can reinforce the pattern even in service of "healthier" goals. Shift to conversation, and mention that a registered dietitian can give tailored guidance. The National Alliance for Eating Disorders helpline is the current referral; NEDA's line has been disconnected.
