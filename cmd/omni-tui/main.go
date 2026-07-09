package main

import (
	"flag"
	"fmt"
	"os"

	tea "charm.land/bubbletea/v2"

	"github.com/syscode-labs/omni-on-unraid/internal/omnitui"
)

var version = "dev"

func main() {
	showVersion := flag.Bool("version", false, "print version and exit")
	flag.Parse()

	if *showVersion {
		fmt.Println(omnitui.VersionString(version))
		return
	}

	program := tea.NewProgram(omnitui.NewModel(omnitui.DefaultActions()))
	if _, err := program.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "omni-tui: %v\n", err)
		os.Exit(1)
	}
}
