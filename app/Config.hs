{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ViewPatterns #-}

module Config where

import Control.Applicative ((<|>))
import Data.Coerce (coerce)
import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Maybe (fromMaybe)
import qualified Data.Text as T
import Lens.Micro
import Lens.Micro.Extras (view)
import NvFetcher.NixFetcher
import NvFetcher.Types
import NvFetcher.Types.Lens
import Toml (TOML, TomlCodec, (.=))
import qualified Toml
import Validation (validationToEither)

parseConfig :: TOML -> Either [Toml.TomlDecodeError] [Package]
parseConfig toml = go tables [] []
  where
    go (Left errs : xs) se sp = go xs (se <> errs) sp
    go (Right x : xs) se sp = go xs se (x : sp)
    go [] [] sp = Right sp
    go [] se _ = Left se
    tables = [fmap (toPackage k) $ validationToEither $ Toml.runTomlCodec iCodec v | (Toml.unKey -> (Toml.unPiece -> k) :| _, v) <- Toml.toList $ Toml.tomlTables toml]
    toPackage k (v, f, g@GitOptions {..}) =
      let f' v = case f v of
            x@FetchGit {} ->
              x
                & branch .~ goBranch
                & deepClone .~ fromMaybe False goDeepClone
                & fetchSubmodules .~ fromMaybe False goFetchSubmodules
                & leaveDotGit .~ fromMaybe False goLeaveDotGit
            x ->
              if not $ isGitOptionsDefault g
                then error $ "Try to set git-prefetch configuration for a url fetcher: " <> show x
                else x
       in Package k v f'
    iCodec = (,,) <$> versionSourceCodec .= (view _1) <*> fetcherCodec .= (view _2) <*> gitOptionsCodec .= (view _3)

versionSourceCodec :: TomlCodec VersionSource
versionSourceCodec =
  Toml.dimatch
    ( \case
        GitHubRelease {..} -> Just GitHubRelease {..}
        _ -> Nothing
    )
    id
    ( Toml.textBy
        ( \case
            GitHubRelease {..} -> _owner <> "/" <> _repo
            _ -> error "impossible"
        )
        ( \x -> case T.split (== '/') x of
            [_owner, _repo] -> Right GitHubRelease {..}
            _ -> Left "unexpected github srouce: it should be something like [owner]/[repo]"
        )
        "src.github"
    )
    <|> Toml.dimatch
      ( \case
          Git {..} -> Just _vurl
          _ -> Nothing
      )
      Git
      (Toml.text "src.git")
    <|> Toml.dimatch
      ( \case
          Pypi {..} -> Just _pypi
          _ -> Nothing
      )
      Pypi
      (Toml.text "src.pypi")
    <|> Toml.dimatch
      ( \case
          ArchLinux {..} -> Just _archpkg
          _ -> Nothing
      )
      ArchLinux
      (Toml.text "src.archpkg")
    <|> Toml.dimatch
      ( \case
          Aur {..} -> Just _aur
          _ -> Nothing
      )
      Aur
      (Toml.text "src.aur")
    <|> Toml.dimatch
      ( \case
          Manual {..} -> Just _manual
          _ -> Nothing
      )
      Manual
      (Toml.text "src.manual")
    <|> Toml.dimatch
      ( \case
          Repology {..} -> Just Repology {..}
          _ -> Nothing
      )
      id
      ( Toml.textBy
          ( \case
              Repology {..} -> _repology <> ":" <> _repo
              _ -> error "impossible"
          )
          ( \t -> case T.split (== ':') t of
              [_repology, _repo] -> Right Repology {..}
              _ -> Left "unexpected repology source: it should be something like [project]:[repo]"
          )
          "src.repology"
      )

unsupportError :: a
unsupportError = error "serialization is unsupported"

-- | Use it only for deserialization!!!
fetcherCodec :: TomlCodec PackageFetcher
fetcherCodec =
  Toml.textBy
    unsupportError
    ( \t -> case T.split (== '/') t of
        [owner, rest] -> case T.split (== ':') rest of
          [repo, rawV] ->
            Right $ \(coerce -> realV) -> gitHubFetcher (owner, repo) $ coerce $ T.replace "$ver" rawV realV
          [repo] -> Right $ gitHubFetcher (owner, repo)
          _ -> Left "unexpected github fetcher: it should be something like [owner]/[repo] or [owner]/[repo]:[ver]"
        _ -> Left "unexpected github fetcher: it should be something like [owner]/[repo] or [owner]/[repo]:[ver]"
    )
    "fetch.github"
    <|> Toml.textBy
      unsupportError
      ( \t -> case T.split (== ':') t of
          [fpypi, rawV] ->
            Right $ \(coerce -> realV) -> pypiFetcher fpypi $ coerce $ T.replace "$ver" rawV realV
          [fpypi] -> Right $ pypiFetcher fpypi
          _ -> Left "unexpected pypi fetcher: it should be something like [pypi] or [pypi]:[ver]"
      )
      "fetch.pypi"
    <|> Toml.textBy
      unsupportError
      ( \t -> case T.split (== ':') t of
          [furl, rawV] ->
            Right $ \(coerce -> realV) -> gitFetcher furl $ coerce $ T.replace "$ver" rawV realV
          [furl] -> Right $ gitFetcher furl
          _ -> Left "unexpected git fetcher: it should be something like [git_url] or [git_url]:[ver]"
      )
      "fetch.git"
    <|> Toml.textBy
      unsupportError
      (\t -> Right $ \(coerce -> v) -> urlFetcher $ T.replace "$ver" v t)
      "fetch.url"

data GitOptions = GitOptions
  { goBranch :: Maybe T.Text,
    goDeepClone :: Maybe Bool,
    goFetchSubmodules :: Maybe Bool,
    goLeaveDotGit :: Maybe Bool
  }
  deriving (Eq)

isGitOptionsDefault :: GitOptions -> Bool
isGitOptionsDefault = (== GitOptions Nothing Nothing Nothing Nothing)

gitOptionsCodec :: TomlCodec GitOptions
gitOptionsCodec =
  GitOptions
    <$> Toml.dioptional (Toml.text "git.branch") .= goBranch
    <*> Toml.dioptional (Toml.bool "git.deepClone") .= goDeepClone
    <*> Toml.dioptional (Toml.bool "git.fetchSubmodules") .= goFetchSubmodules
    <*> Toml.dioptional (Toml.bool "git.leaveDotGit") .= goLeaveDotGit
