# Transition side edges and final mask — 2026-09-09

## Scope and confirmed causes

- The opaque destination-background backing remained visible beside aspect-fit screenshots and through transparent screenshot edges. It was baked into the transition PNG, not added by Composer.
- The terminal PNG already had final mask colors, but the live overlay explicitly animated `magicMove.colors` from opaque to faded for the spring duration. This caused visible fade formation near arrival.

## Minimal fix

- Remove the solid backing. Keep a fixed, transparent shadow container whose screenshot child supplies the alpha silhouette; screenshot coordinates and flight animations are unchanged.
- Keep the independent shadow disabled during shutter, enabled at takeover, and within the existing content mask.
- Set final mask colors under the opaque shutter without a color animation. Retain only the existing mask-coordinate animations that follow flight geometry.
- Icon/title remain outside the mask. No changes to Composer, official apps, activation, spring parameters, sound, or control actions.

## Verification

- Regression tests first reproduced opaque white side pixels and the unwanted mask-color animation.
- Targeted tests: 22 passed.
- Full suite: 173 passed in 723.360 seconds.
- Production rendering with a real captured window produced light/dark previews.
  Visual inspection found no solid side backing, a completed lower fade, and clear
  icon/title. Shadow pixel checks passed around the actual aspect-fit image silhouette.
  Local previews and logs are intentionally excluded from Git.
- Independent review was unavailable because the reviewer hit its usage limit; it is not counted as passed.
- Installation and physical double-Command acceptance are recorded separately below. Render QA is not live Composer acceptance; production overlay is excluded from ordinary screen recordings.

## Installed runtime

- Installed from authoritative staging through the existing workflow, after stopping only verified canonical processes.
- Generated build identity, signature, and running executable vnode matched the
  canonical installation; AX/Screen Recording were granted and doctor reported
  `Overall: healthy`.
- The non-authoritative Documents-side dist copy regained FinderInfo, as previously documented. It was not used as the installation source and does not affect canonical health.
- User asked to generate a fresh Appshot and confirm edge/fade behavior. Physical visual acceptance remains pending; existing cards retain their old PNGs.
