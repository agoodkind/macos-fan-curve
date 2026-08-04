def release_list:
  if length > 0 and (.[0] | type) == "array" then
    add
  else
    .
  end;

def matches_stable_tag:
  .tag_name | test("^[0-9]{2}\\.[0-9]{1,2}\\.[0-9]{1,2}(-r[1-9][0-9]*)?$");

def matches_track:
  if $release_track == "prerelease" then
    .prerelease == true
  elif $release_track == "stable" then
    .prerelease == false and matches_stable_tag
  else
    error("release_track must be prerelease or stable")
  end;

release_list
| map(select(.draft == false and matches_track))
| map(
    . as $release
    | [
        .assets[]
        | select(
            (.name | startswith($asset_prefix))
            and (.name | endswith($asset_suffix))
          )
      ] as $matching_assets
    | select(($matching_assets | length) == 1)
    | {
        tag_name: $release.tag_name,
        asset_name: $matching_assets[0].name
      }
  )
| .[:$release_limit]
| .[]
| [.tag_name, .asset_name]
| @tsv
