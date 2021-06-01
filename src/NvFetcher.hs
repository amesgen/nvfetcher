{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ViewPatterns #-}

-- | Copyright: (c) 2021 berberman
-- SPDX-License-Identifier: MIT
-- Maintainer: berberman <berberman@yandex.com>
-- Stability: experimental
-- Portability: portable
--
-- The main module of nvfetcher. If you want to create CLI program with it, it's enough to import only this module.
--
-- Example:
--
-- @
-- module Main where
--
-- import NvFetcher
--
-- main :: IO ()
-- main = runNvFetcher defaultArgs packageSet
--
-- packageSet :: PackageSet ()
-- packageSet = do
--   define $ package "feeluown-core" `fromPypi` "feeluown"
--   define $ package "qliveplayer" `fromGitHub` ("IsoaSFlus", "QLivePlayer")
-- @
--
-- You can find more examples of packages in @Main_example.hs@.
--
-- Running the created program:
--
-- * @main@ -- abbreviation of @main build@
-- * @main build@ -- build nix sources expr from given @packageSet@
-- * @main clean@ -- delete .shake dir and generated nix file
-- * @main -j@ -- build with parallelism
--
-- All shake options are inherited.
module NvFetcher
  ( Args (..),
    defaultArgs,
    runNvFetcher,
    module NvFetcher.PackageSet,
    module NvFetcher.Types,
    module NvFetcher.Types.ShakeExtras,
  )
where

import Data.Text (Text)
import qualified Data.Text as T
import Development.Shake
import NeatInterpolation (trimming)
import NvFetcher.Core
import NvFetcher.NixFetcher
import NvFetcher.Nvchecker
import NvFetcher.PackageSet
import NvFetcher.Types.ShakeExtras
import NvFetcher.Types

-- | Arguments for running nvfetcher
data Args = Args
  { -- | Shake options
    argShakeOptions :: ShakeOptions,
    -- | Build target
    argTarget :: String,
    -- | Output file path
    argOutputFilePath :: FilePath,
    -- | Custom rules
    argRules :: Rules (),
    -- | Action run after build rule
    argActionAfterBuild :: Action (),
    -- | Action run after clean rule
    argActionAfterClean :: Action ()
  }

-- | Default arguments of 'defaultMain'
--
-- Output file path is @sources.nix@.
defaultArgs :: Args
defaultArgs =
  Args
    ( shakeOptions
        { shakeProgress = progressSimple
        }
    )
    "build"
    "sources.nix"
    (pure ())
    (pure ())
    (pure ())

-- | Entry point of nvfetcher
runNvFetcher :: Args -> PackageSet () -> IO ()
runNvFetcher args@Args {..} packageSet = do
  pkgs <- runPackageSet packageSet
  shakeExtras <- initShakeExtras pkgs
  let opts =
        argShakeOptions
          { shakeExtra = addShakeExtra shakeExtras (shakeExtra argShakeOptions)
          }
      rules = mainRules args
  shake opts $ want [argTarget] >> rules

mainRules :: Args -> Rules ()
mainRules Args {..} = do
  "clean" ~> do
    removeFilesAfter ".shake" ["//*"]
    removeFilesAfter "." [argOutputFilePath]
    argActionAfterClean

  "build" ~> do
    allKeys <- getAllPackageKeys
    body <- parallel $ generateNixSourceExpr <$> allKeys
    getVersionChanges >>= \changes ->
      if null changes
        then putInfo "Up to date"
        else do
          putInfo "Changes:"
          putInfo $ unlines $ show <$> changes
    writeFileChanged argOutputFilePath $ T.unpack $ srouces (T.unlines body) <> "\n"
    putInfo $ "Generate " <> argOutputFilePath
    argActionAfterBuild

  argRules
  coreRules

srouces :: Text -> Text
srouces body =
  [trimming|
    # This file was generated by nvfetcher, please do not modify it manually.
    { fetchgit, fetchurl }:
    {
      $body
    }
  |]