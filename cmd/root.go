package cmd

import "github.com/spf13/cobra"

var rootCmd = &cobra.Command{
	Use:   "dotfiles",
	Short: "Manage your development environment",
}

func Execute() {
	cobra.CheckErr(rootCmd.Execute())
}
