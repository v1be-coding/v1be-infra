# What a branch environment adds to CI's rights: its own bucket and distribution.
# Portfolio only, because café roles never deploy a branch (ADR-0011).

locals {
  branch_buckets = "arn:aws:s3:::${local.site_bucket_prefix}-pr-*"
  distributions  = "arn:aws:cloudfront::${var.account_id}:distribution/*"
}

data "aws_iam_policy_document" "branch" {
  count = var.account == "portfolio" ? 1 : 0

  # The names rule out production's bucket, which ends in the account's name.
  statement {
    sid       = "ManageBranchSites"
    actions   = ["s3:*"]
    resources = [local.branch_buckets, "${local.branch_buckets}/*"]
  }

  # Cache policies and the origin access control are read here and never written,
  # because AWS can't scope either (ADR-0011). The origin secret isn't readable:
  # it's in a KeyValueStore, under a different service prefix.
  statement {
    sid       = "ReadEdge"
    actions   = ["cloudfront:Get*", "cloudfront:List*"]
    resources = ["*"]
  }

  # CreateDistribution has no resource type, so only the tag can limit it.
  statement {
    sid       = "CreateTaggedDistributions"
    actions   = ["cloudfront:CreateDistribution"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/episode"
      values   = [var.name]
    }
  }

  # IfExists because a new distribution has no tags yet.
  statement {
    sid       = "TagDistributions"
    actions   = ["cloudfront:TagResource"]
    resources = [local.distributions]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/episode"
      values   = [var.name]
    }

    condition {
      test     = "StringEqualsIfExists"
      variable = "aws:ResourceTag/episode"
      values   = [var.name]
    }
  }

  statement {
    sid = "ManageOwnDistributions"
    actions = [
      "cloudfront:CreateInvalidation",
      "cloudfront:DeleteDistribution",
      "cloudfront:UntagResource",
      "cloudfront:UpdateDistribution",
    ]
    resources = [local.distributions]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/episode"
      values   = [var.name]
    }
  }

  # Editing a production distribution could expose the origin secret (ADR-0010).
  # They have no episode tag, so TagDistributions alone would let CI add one. This
  # deny closes that, and every distribution this stack makes carries the tag.
  statement {
    sid    = "KeepOffProductionEdge"
    effect = "Deny"
    actions = [
      "cloudfront:DeleteDistribution",
      "cloudfront:TagResource",
      "cloudfront:UntagResource",
      "cloudfront:UpdateDistribution",
    ]
    resources = [local.distributions]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/stack"
      values   = ["episodes"]
    }
  }
}
