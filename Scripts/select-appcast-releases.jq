def release_list:
  if length > 0 and (.[0] | type) == "array" then
    add
  else
    .
  end;

def matches_track:
  if $release_track == "prerelease" then
    .prerelease == true
  elif $release_track == "stable" then
    .prerelease == false
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
