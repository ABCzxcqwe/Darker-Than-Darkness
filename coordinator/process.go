package main

import (
	"os"
	"os/exec"
	"strings"
)

// splitCommand separa una plantilla en tokens respetando comillas dobles.
func splitCommand(tpl string) []string {
	var tokens []string
	var cur strings.Builder
	inQuotes := false
	flush := func() {
		if cur.Len() > 0 {
			tokens = append(tokens, cur.String())
			cur.Reset()
		}
	}
	for _, r := range tpl {
		switch r {
		case '"':
			inQuotes = !inQuotes
		case ' ', '\t', '\n', '\r':
			if inQuotes {
				cur.WriteRune(r)
			} else {
				flush()
			}
		default:
			cur.WriteRune(r)
		}
	}
	flush()
	return tokens
}

// buildCommand arma el comando reemplazando placeholders token por token,
// de modo que valores con espacios queden dentro del mismo argumento.
func buildCommand(tpl string, repl map[string]string) (string, []string) {
	tokens := splitCommand(tpl)
	for i, t := range tokens {
		for k, v := range repl {
			t = strings.ReplaceAll(t, "{"+k+"}", v)
		}
		tokens[i] = t
	}
	if len(tokens) == 0 {
		return "", nil
	}
	return tokens[0], tokens[1:]
}

func startProcess(bin string, args []string) (*exec.Cmd, error) {
	cmd := exec.Command(bin, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	return cmd, nil
}
