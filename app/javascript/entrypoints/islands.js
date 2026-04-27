import React from 'react'
import ReactDOM from 'react-dom/client'
import MadminArrayFieldIsland from '../islands/components/MadminArrayFieldIsland.jsx'
import ToastIsland from '../islands/components/ToastIsland.jsx'
import ChatIsland from '../islands/components/ChatIsland.jsx'
import ChatSidebarIsland from '../islands/components/ChatSidebarIsland.jsx'
import NotificationsIconIsland from '../islands/components/NotificationsIconIsland.jsx'
import NotificationsIsland from '../islands/components/NotificationsIsland.jsx'
import UserMenuDropdownIsland from '../islands/components/UserMenuDropdownIsland.jsx'
import SettingsSidebarIsland from '../islands/components/SettingsSidebarIsland.jsx'

// Expose React and ReactDOM globally for islandjs-rails mount scripts
window.React = React
window.ReactDOM = ReactDOM

// NOTE: The components exported here must be islandjs-rails React components that take containerId string as their ONLY prop (unique quirk!)
// This islands.js entry point is used by the islandjs-rails gem to load island components into the ERB views.
// islandjs-rails gem react_component helper will generate the containerId prop and pass it to the component when it is rendered.
// These islands components must use the useTurboProps and useTurboCache hooks to access the data passed from the react_component helper.
// <%= react_component('ComponentName', { key: value, key2: value2 }) %> will generate the containerId prop make the data passed in the hash available to the component via the useTurboProps hook.
// import { useTurboProps, useTurboCache } from '../utils/turbo'; // To import the hooks
// const initialProps = useTurboProps(containerId); // To set up the initial properties
// useTurboCache(containerId, currentProps, true); // For Turbo-aware state persistence
// Components defined in app/javascript/pages/ are not islands and should not use the useTurboProps and useTurboCache hooks and should not be exported here.
// Components defined in app/javascript/pages/ use inertia_rails gem to render the page and do not need to be exported here.
// islandjs-rails React components are preferred for any time complex state and interactivity is needed within ERB views.

window.islandjsRails = {
  MadminArrayFieldIsland,
  ToastIsland,
  ChatIsland,
  ChatSidebarIsland,
  NotificationsIconIsland,
  NotificationsIsland,
  UserMenuDropdownIsland,
  SettingsSidebarIsland,
}

