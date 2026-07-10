# Input sanitization
#
# Student identifiers arrive as free-text (e.g. "Alice Smith!") and must be
# converted into safe, DNS/AWS-friendly identifiers WITHOUT ever failing the
# run, per the assessment's "Input sanitization" requirement.
#
# Steps, applied per raw string:
#   1. lower()                         -> "alice smith!"
#   2. replace non [a-z0-9] runs -> "-" -> "alice-smith-"   (also collapses
#                                          repeated separators in one pass,
#                                          since the regex is a "+" match)
#   3. trim leading/trailing "-"        -> "alice-smith"
#   4. fall back to "student-<index>"   if the result is empty (e.g. an
#                                          input of just "!!!")
#
# Resource *keys* (used in every module's for_each) are NOT the sanitized
# name alone. Two different raw inputs can sanitize to the same string
# (e.g. "Alice Smith" and "alice_smith"), and for_each requires unique keys.
# We guard against that by appending the original list index to build a
# guaranteed-unique resource_key, while still exposing the clean sanitized
# name for tags, hostnames, and anything human-facing.
locals {
  sanitized_candidates = [
    for raw in var.students :
    trim(replace(lower(raw), "/[^a-z0-9]+/", "-"), "-")
  ]

  student_records = [
    for idx, raw in var.students : {
      index        = idx
      raw          = raw
      sanitized_id = local.sanitized_candidates[idx] != "" ? local.sanitized_candidates[idx] : "student-${idx}"
      resource_key = "${local.sanitized_candidates[idx] != "" ? local.sanitized_candidates[idx] : "student-${idx}"}-${idx}"
    }
  ]

  # Keyed by resource_key so every module can safely for_each over this map.
  students = { for r in local.student_records : r.resource_key => r }
}

# Non-fatal collision check: if sanitization produces duplicate names, this
# reports it in `terraform plan/apply` output without failing the run
# (Terraform `check` blocks never block apply). Resources still deploy
# correctly because resource_key is index-guaranteed unique either way; this
# is purely an operator signal that two students now share a display name.
check "sanitized_student_names_unique" {
  assert {
    condition     = length(distinct([for r in local.student_records : r.sanitized_id])) == length(local.student_records)
    error_message = "Two or more students sanitized to the same identifier. Resources were still created safely (index-suffixed internally), but Owner tags may look ambiguous -- consider disambiguating the roster input."
  }
}
