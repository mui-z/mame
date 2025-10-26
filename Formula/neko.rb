class Neko < Formula
  desc "Filesystem-driven mock HTTP server"
  homepage "https://github.com/osushi/neko"
  license "MIT"
  head "https://github.com/osushi/neko.git", branch: "main"

  depends_on xcode: ["14.0", :build]

  def install
    system "swift", "build", "--configuration", "release"
    bin.install ".build/release/neko"
  end

  test do
    system "#{bin}/neko", "--help"
  end
end
