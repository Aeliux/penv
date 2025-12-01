package index

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
)

var RemoteIndex = "https://raw.githubusercontent.com/Aeliux/penv/master/index3.json"

func GetRemoteIndex() (RemoteIndex3, error) {
	var remoteIndex RemoteIndex3
	buffer := new(bytes.Buffer)
	err := GetFile(RemoteIndex, buffer)
	if err != nil {
		return remoteIndex, err
	}

	err = json.Unmarshal(buffer.Bytes(), &remoteIndex)
	if err != nil {
		return remoteIndex, err
	}

	return remoteIndex, nil
}

func GetFile(url string, target io.Writer) error {
	resp, err := http.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	_, err = io.Copy(target, resp.Body)
	if err != nil {
		return err
	}

	return nil
}

func GetFileSize(url string) (int64, error) {
	resp, err := http.Head(url)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()

	return resp.ContentLength, nil
}

func CalculateSha256(reader io.Reader) (string, error) {
	hasher := sha256.New()
	_, err := io.Copy(hasher, reader)
	if err != nil {
		return "", err
	}

	return hex.EncodeToString(hasher.Sum(nil)), nil
}
