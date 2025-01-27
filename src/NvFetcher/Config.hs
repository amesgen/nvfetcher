-- | Copyright: (c) 2021-2022 berberman
-- SPDX-License-Identifier: MIT
-- Maintainer: berberman <berberman@yandex.com>
-- Stability: experimental
-- Portability: portable
module NvFetcher.Config where

import Data.Default
import Development.Shake

-- | Nvfetcher configuration
data Config = Config
  { shakeConfig :: ShakeOptions,
    buildDir :: FilePath,
    customRules :: Rules (),
    actionAfterBuild :: Action (),
    actionAfterClean :: Action (),
    retry :: Int,
    filterRegex :: Maybe String,
    cacheNvchecker :: Bool,
    -- | Absolute path
    keyfile :: Maybe FilePath
  }

instance Default Config where
  def =
    Config
      { shakeConfig =
          shakeOptions
            { shakeProgress = progressSimple,
              shakeThreads = 0
            },
        buildDir = "_sources",
        customRules = pure (),
        actionAfterBuild = pure (),
        actionAfterClean = pure (),
        retry = 3,
        filterRegex = Nothing,
        cacheNvchecker = True,
        keyfile = Nothing
      }
