/// <reference types="@raycast/api">

/* 🚧 🚧 🚧
 * This file is auto-generated from the extension's manifest.
 * Do not modify manually. Instead, update the `package.json` file.
 * 🚧 🚧 🚧 */

/* eslint-disable @typescript-eslint/ban-types */

type ExtensionPreferences = {
  /** Executable Path - Path to pi binary (default: /opt/homebrew/bin/pi, fallback to /usr/local/bin/pi or $PATH) */
  "executablePath": string,
  /** Search Mode - Search retrieval mode */
  "searchMode": "hybrid" | "vector" | "keyword",
  /** Minimum Similarity - Minimum vector similarity percentage (default: 35%) */
  "minSimilarity": string,
  /** Result Limit - Number of results to display (default: 15) */
  "resultLimit": string
}

/** Preferences accessible in all the extension's commands */
declare type Preferences = ExtensionPreferences

declare namespace Preferences {
  /** Preferences accessible in the `search` command */
  export type Search = ExtensionPreferences & {}
}

declare namespace Arguments {
  /** Arguments passed to the `search` command */
  export type Search = {}
}

