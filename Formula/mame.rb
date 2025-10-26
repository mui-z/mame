class Mame < Formula
  desc "Filesystem-driven mock HTTP server"
  homepage "https://github.com/osushi/mame"
  license "MIT"
  head "https://github.com/osushi/mame.git", branch: "main"

  depends_on xcode: ["14.0", :build]

  def install
    system "swift", "build", "--configuration", "release"
    bin.install ".build/release/mame"
  end

  test do
    system "#{bin}/mame", "--help"
  end
end
