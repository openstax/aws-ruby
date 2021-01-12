# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Added additional method to msk stack, to return sorted list of bootstrap brokers

Replaced Travis with GH Actions

All secret types now default to SecureString, not just the RSA keys

Added CloudFormation ERB templates (cfn files that end in .yml.erb)

Gracefully handle interrupts while running Packer and return Packer's exit status from the call

## [1.1.0] - 2020-10-20

Fixed Packer debug mode by reading and printing each character from Packer instead of each line.

Restricted AMI search to images owned by the same account to prevent a potential security flaw.

Gitignored Gemfile.lock.

Removed development dependency on bundler 1.

## [1.0.0] - 2020-10-03

First official version.
