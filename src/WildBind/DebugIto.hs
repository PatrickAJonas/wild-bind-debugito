{-# LANGUAGE FlexibleContexts, PartialTypeSignatures #-}
{-# OPTIONS_GHC -fno-warn-partial-type-signatures  #-}
-- |
-- Module: WildBind.DebugIto
-- Description: Bindings used by debugito
-- Maintainer: Toshio Ito <debug.ito@gmail.com>
-- 
module WildBind.DebugIto
       ( -- * Actions
         push,
         pushes,
         cmd',
         -- * Simple Binding
         base,
         -- * Global
         GlobalConfig(..),
         global,
         -- * Video players
         VideoPlayerConfig(..),
         videoPlayer,
         dvdPlayer,
         forTotem,
         forVLC,
         -- * Thunar
         thunar,
         thunarMenu,
         -- * GIMP
         GimpConfig(..),
         defGimpConfig,
         gimp,
         -- * Firefox
         FirefoxConfig(..),
         defFirefoxConfig,
         firefox
       ) where

import Control.Monad (void, forM_)
import Control.Monad.Trans (MonadIO(liftIO), lift)
import Control.Monad.Reader (MonadReader, ReaderT)
import qualified Control.Monad.State as State
import Data.Monoid ((<>), mempty)
import Data.Text (Text, isInfixOf, isSuffixOf, unpack)
import System.Process (callCommand, spawnCommand)
import WildBind.Input.NumPad (NumPadUnlocked(..))
import WildBind.Binding
  ( Binding, Binding',
    binds, on, as, run,
    whenFront,
    startFrom, ifBack, binds', extend,
    advice, before, after,
    bindsF, bindsF'
  )
import WildBind.X11
  ( winClass, winInstance, winName, ActiveWindow, Window,
    ToXKeyEvent, X11Front,
    alt, ctrl, shift, press
  )
import WildBind.X11.Emulate (push)
import WildBind.X11.KeySym

-- | Push a sequence of keys
pushes :: (ToXKeyEvent k, MonadIO m, MonadReader Window m) => X11Front i -> [k] -> m ()
pushes x11 = mapM_ (push x11)

-- | Run a command in background.
cmd' :: MonadIO m => String -> m ()
cmd' = liftIO . void . spawnCommand

-- | Basic, easily overridden bindings
base :: X11Front i -> Binding ActiveWindow NumPadUnlocked
base x11 = bindsF $ do
  on NumCenter `as` "Enter" `run` push x11 xK_Return


data GlobalConfig =
  GlobalConfig
  { globalMaximize :: ReaderT ActiveWindow IO (),
    -- ^ action to maximize the active window.
    globalMenu :: ReaderT ActiveWindow IO ()
    -- ^ action to open the menu window.
  }

-- | Binding that should be globally active
global :: X11Front i -> GlobalConfig -> Binding ActiveWindow NumPadUnlocked
global x11 conf = global_nostate <> global_non_switcher where
  global_nostate = bindsF $ do
    on NumMinus `as` "Close" `run` push x11 (alt xK_F4)
    on NumPlus `as` "Maximize" `run` globalMaximize conf
    on NumMulti `as` "Menu" `run` globalMenu conf
  global_non_switcher = whenFront (\w -> winInstance w /= "boring-window-switcher") $ binds $ do
    on NumEnter `as` "Switch" `run` cmd' "boring-window-switcher"


data VideoPlayerConfig =
  VideoPlayerConfig
  { vpPlayPause, vpVolumeUp, vpVolumeDown,
    vpBackNormal, vpForwardNormal,
    vpBackBig, vpForwardBig,
    vpBackSmall, vpForwardSmall,
    vpToggleFull,
    vpToggleDVDMenu :: ReaderT ActiveWindow IO ()
  }

data PlayerMode = NormalPlayer | DVDPlayer deriving (Show, Eq, Ord)

videoPlayerBase :: VideoPlayerConfig -> Binding' PlayerMode ActiveWindow NumPadUnlocked
videoPlayerBase conf = (ifBack (== NormalPlayer) normal_mode dvd_mode) <> common where
  act field = lift $ field conf
  normal_mode = bindsF' $ do
    on NumHome `as` "Back (L)" `run` act vpBackBig
    on NumUp `as` "Vol up" `run` act vpVolumeUp
    on NumPageUp `as` "Forward (L)" `run` act vpForwardBig
    on NumLeft `as` "Back (M)" `run` act vpBackNormal
    on NumCenter `as` "Play/Pause" `run` act vpPlayPause
    on NumRight `as` "Forward (M)" `run` act vpForwardNormal
    on NumEnd `as` "Back (S)" `run` act vpBackSmall
    on NumDown `as` "Vol down" `run` act vpVolumeDown
    on NumPageDown `as` "Forward (S)" `run` act vpForwardSmall
    on NumDelete `as` "DVD Mode" `run` State.put DVDPlayer
  dvd_mode = bindsF' $ do
    on NumDelete `as` "Normal Mode" `run` State.put NormalPlayer
    on NumPageDown `as` "Toggle Menu" `run` act vpToggleDVDMenu
  common = bindsF' $ do
    on NumInsert `as` "Toggle Full Screen" `run` act vpToggleFull

videoPlayer :: VideoPlayerConfig -> Binding ActiveWindow NumPadUnlocked
videoPlayer = startFrom NormalPlayer . videoPlayerBase

dvdPlayer :: VideoPlayerConfig -> Binding ActiveWindow NumPadUnlocked
dvdPlayer = startFrom DVDPlayer . videoPlayerBase

forTotem :: X11Front k -> (VideoPlayerConfig -> Binding ActiveWindow i) -> Binding ActiveWindow i
forTotem x11 maker = whenFront (\w -> winInstance w == "totem") $ maker conf where
  push' :: (ToXKeyEvent k, _) => k -> _
  push' = push x11
  conf = VideoPlayerConfig
         { vpPlayPause = push' xK_p,
           vpVolumeUp = push' xK_Up,
           vpVolumeDown = push' xK_Down,
           vpBackNormal = push' xK_Left,
           vpForwardNormal = push' xK_Right,
           vpBackBig = push' (ctrl xK_Left),
           vpForwardBig = push' (ctrl xK_Right),
           vpBackSmall = push' (shift xK_Left),
           vpForwardSmall = push' (shift xK_Right),
           vpToggleFull = push' xK_f,
           vpToggleDVDMenu = push' xK_m
         }

forVLC :: X11Front k -> (VideoPlayerConfig -> Binding ActiveWindow i) -> Binding ActiveWindow i
forVLC x11 maker = whenFront (\w -> winInstance w == "vlc") $ maker conf where
  push' :: (ToXKeyEvent k, _) => k -> _
  push' = push x11
  conf = VideoPlayerConfig
         { vpPlayPause = push' xK_space,
           vpVolumeUp = push' (ctrl xK_Up),
           vpVolumeDown = push' (ctrl xK_Down),
           vpBackNormal = push' (alt xK_Left),
           vpForwardNormal = push' (alt xK_Right),
           vpBackBig = push' (ctrl xK_Left),
           vpForwardBig = push' (ctrl xK_Right),
           vpBackSmall = push' (shift xK_Left),
           vpForwardSmall = push' (shift xK_Right),
           vpToggleFull = push' xK_f,
           vpToggleDVDMenu = push' (shift xK_M)
         }

thunar :: X11Front i -> Binding ActiveWindow NumPadUnlocked
thunar x11 = whenFront (\w -> winInstance w == "Thunar" && winClass w == "Thunar") $ bindsF $ do
  on NumHome `as` "Home directory" `run` push x11 (alt xK_Home)
  on NumPageUp `as` "Parent directory" `run` push x11 (alt xK_Up)

thunarMenu :: X11Front i
           -> Text -- ^ a string that should be part of the menu window's title.
           -> Binding ActiveWindow NumPadUnlocked
thunarMenu x11 menu_window_name_part = whenFront frontCondition $ thunar x11 <> ext where
  frontCondition w = menu_window_name_part `isInfixOf` winName w
  ext = bindsF $ do
    on NumCenter `as` "Run" `run` do
      push x11 xK_Return
      cmd' ("sleep 0.3; xdotool search --name '" ++ unpack menu_window_name_part ++ "' windowkill")


data GimpConfig = GimpConfig { gimpSwapColor :: ReaderT ActiveWindow IO ()
                             }

defGimpConfig :: X11Front i -> GimpConfig
defGimpConfig x11 = GimpConfig { gimpSwapColor = push x11 xK_F12 }

-- | Binding for GIMP.
gimp :: X11Front i -> GimpConfig -> Binding ActiveWindow NumPadUnlocked
gimp x11 conf = whenFront (\w -> "Gimp" `isInfixOf` winClass w) $ bindsF $ do
  on NumCenter `as` "ペン" `run` push' xK_p
  on NumDelete `as` "鉛筆" `run` push' xK_n
  on NumLeft `as` "スポイト" `run` push' xK_o
  on NumRight `as` "消しゴム" `run` push' (shift xK_E)
  on NumHome `as` "矩形選択" `run` push' xK_r
  on NumUp `as` "色スワップ" `run` gimpSwapColor conf
  on NumPageUp `as` "パス" `run` push' xK_o
  on NumEnd `as` "やり直し" `run` push' (ctrl xK_z)
  on NumDown `as` "縮小" `run` push' xK_minus
  on NumInsert `as` "保存" `run` push' (ctrl xK_s)
  on NumPageDown `as` "拡大" `run` push' xK_plus
  where
    push' :: (ToXKeyEvent k, _) => k -> _
    push' = push x11


data FirefoxConfig = FirefoxConfig { ffCancel,
                                     ffLeftTab, ffRightTab, ffCloseTab,
                                     ffToggleBookmarks,
                                     ffLink, ffLinkNewTab,
                                     ffReload,
                                     ffBack, ffForward, ffHome,
                                     ffRestoreTab,
                                     ffFontNormal, ffFontBigger, ffFontSmaller :: ReaderT ActiveWindow IO ()
                                   }

defFirefoxConfig :: X11Front i -> FirefoxConfig
defFirefoxConfig x11 =
  FirefoxConfig
  { ffCancel = push' (ctrl xK_g),
    ffLeftTab = push' (shift $ ctrl xK_Tab),
    ffRightTab = push' (ctrl xK_Tab),
    ffCloseTab = pushes' [ctrl xK_q, ctrl xK_w],
    ffToggleBookmarks = pushes' [ctrl xK_q, ctrl xK_b],
    ffLink = pushes' [ctrl xK_u, press xK_e],
    ffLinkNewTab = pushes' [ctrl xK_u, shift xK_E],
    ffReload = push' xK_F5,
    ffBack = push' (shift xK_B),
    ffForward = push' (shift xK_F),
    ffHome = push' (alt xK_Home),
    ffRestoreTab = pushes' [ctrl xK_c, press xK_u],
    ffFontNormal = push' (ctrl xK_0),
    ffFontBigger = push' (ctrl xK_plus),
    ffFontSmaller = pushes' [ctrl xK_q, ctrl xK_minus]
  }
  where
    push' :: (ToXKeyEvent k, _) => k -> _
    push' = push x11
    pushes' = pushes x11

data FirefoxState = FFBase | FFExt | FFFont | FFLink | FFBookmark deriving (Show,Eq,Ord)

firefox :: X11Front i -> FirefoxConfig -> Binding ActiveWindow NumPadUnlocked
firefox x11 conf = whenFront (\w -> winInstance w == "Navigator" && winClass w == "Firefox") impl where
  push' :: (ToXKeyEvent k, _) => k -> _
  push' = push x11
  impl = startFrom FFBase
         $ binds_cancel
         <> ( ifBack (== FFBase) binds_base
              $ ifBack (== FFExt) (binds_all_cancel <> binds_ext)
              $ ifBack (== FFFont) (binds_all_cancel <> binds_font)
              $ ifBack (== FFLink) (binds_all_cancel <> binds_link)
              $ ifBack (== FFBookmark) binds_bookmark
              $ mempty
            )
  act field = lift $ field conf
  cancel_act = id `as` "Cancel" `run` (State.put FFBase >> act ffCancel)
  binds_all_cancel = bindsF' $ do
    forM_ (enumFromTo minBound maxBound) $ \k -> on k cancel_act
  binds_cancel = bindsF' $ do
    on NumDelete cancel_act
  binds_base = bindsF' $ do
    on NumLeft `as` "Left tab" `run` act ffLeftTab
    on NumRight `as` "Right tab" `run` act ffRightTab
    on NumEnd `as` "Close tab" `run` act ffCloseTab
    on NumInsert `as` "Bookmark" `run` do
      State.put FFBookmark
      act ffToggleBookmarks
    on NumCenter `as` "Link" `run` do
      State.put FFLink
      act ffLink
    on NumHome `as` "Ext." `run` State.put FFExt
  binds_ext = binds_ext_base <> binds_font
  binds_ext_base = bindsF' $ do
    on NumHome `as` "Link new tab" `run` do
      State.put FFLink
      act ffLinkNewTab
    advice (before $ State.put FFBase) $ do
      on NumPageUp `as` "Reload" `run` act ffReload
      on NumLeft `as` "Back" `run` act ffBack
      on NumRight `as` "Forward" `run` act ffForward
      on NumPageDown `as` "Home" `run` act ffHome
      on NumEnd `as` "Restore tab" `run` act ffRestoreTab
  binds_font = bindsF' $ do
    on NumCenter `as` "Normal font" `run` do
      State.put FFBase
      act ffFontNormal
    advice (before $ State.put FFFont) $ do
      on NumUp `as` "Bigger font" `run` act ffFontBigger
      on NumDown `as` "Smaller font" `run` act ffFontSmaller
  binds_link = bindsF' $ do
    forM_ (enumFromTo minBound maxBound) $ \k -> on k cancel_act
    on NumUp `as` "OK" `run` do
      State.put FFBase
      push' xK_Return
    on NumLeft `as` "4" `run` push' xK_4
    on NumCenter `as` "5" `run` push' xK_5
    on NumRight `as` "6" `run` push' xK_6
  binds_bookmark = bindsF' $ do
    on NumEnd `as` "Tab" `run` push' xK_Tab
    advice (after $ act ffToggleBookmarks) $ do
      forM_ [NumInsert, NumDelete] $ \k -> on k cancel_act
      advice (after $ State.put FFBase) $ do
        on NumCenter `as` "Select (new tab)" `run` push' (ctrl xK_Return)
        on NumHome `as` "Select (cur tab)" `run` push' xK_Return

