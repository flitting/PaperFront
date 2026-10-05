-----BEGIN PGP SIGNED MESSAGE-----
Hash: SHA512

Format: 3.0 (quilt)
Source: espeak-ng
Binary: espeak-ng, espeak-ng-espeak, espeak-ng-data, espeak-ng-data-udeb, libespeak-ng1, libespeak-ng-libespeak1, libespeak-ng-dev, libespeak-ng-libespeak-dev
Architecture: any all
Version: 1.51+dfsg-12build1
Maintainer: Ubuntu Developers <ubuntu-devel-discuss@lists.ubuntu.com>
Uploaders: Samuel Thibault <sthibault@debian.org>
Homepage: https://github.com/espeak-ng/espeak-ng
Standards-Version: 4.6.1
Vcs-Browser: https://salsa.debian.org/a11y-team/espeak-ng
Vcs-Git: https://salsa.debian.org/a11y-team/espeak-ng.git
Testsuite: autopkgtest
Testsuite-Triggers: @builddeps@, clang, libclang-rt-dev
Build-Depends: debhelper-compat (= 13), dh-exec, libpcaudio-dev, libsonic-dev, ronn, kramdown
Package-List:
 espeak-ng deb sound optional arch=any
 espeak-ng-data deb sound optional arch=any
 espeak-ng-data-udeb udeb debian-installer optional arch=any
 espeak-ng-espeak deb sound optional arch=all
 libespeak-ng-dev deb libdevel optional arch=any
 libespeak-ng-libespeak-dev deb libdevel optional arch=any
 libespeak-ng-libespeak1 deb libs optional arch=any
 libespeak-ng1 deb libs optional arch=any
Checksums-Sha1:
 89f6ac8f1ff45b5b506c612fd3b2dadb1a247535 12985129 espeak-ng_1.51+dfsg.orig.tar.gz
 50d418a0860a318f579838703c65385847c65586 51348 espeak-ng_1.51+dfsg-12build1.debian.tar.xz
Checksums-Sha256:
 72242d7c06a4d80f5056335977c5be1ff79ff27bb502d4d054be1803ff787fa9 12985129 espeak-ng_1.51+dfsg.orig.tar.gz
 ccd4411d9efe0604030c604bd7369ec19598bc4d2b6435a0782398e174c0ee54 51348 espeak-ng_1.51+dfsg-12build1.debian.tar.xz
Files:
 69646ee9d1198e4ad4d8b1622c8f15dc 12985129 espeak-ng_1.51+dfsg.orig.tar.gz
 0973fec1f21eeaeebcd58311adc10fb4 51348 espeak-ng_1.51+dfsg-12build1.debian.tar.xz
Original-Maintainer: Debian Accessibility Team <pkg-a11y-devel@alioth-lists.debian.net>

-----BEGIN PGP SIGNATURE-----

iQJHBAEBCgAxFiEET7WIqEwt3nmnTHeHb6RY3R2wP3EFAmYUFAATHGp1bGlhbmtA
dWJ1bnR1LmNvbQAKCRBvpFjdHbA/cfvqD/wKEGoeLT1rAJDNWioH40geepGqbBrY
Bg14vIlmQNYJ0U1g9FYKd/qst6ZM6u5gaeyLvjg4WwVFMbwMBR7lYA2H/6rgc6AE
aYoiDVKaNS5NHWbhIG8JqD4Og04NqgO/Z5uD8/GmqQeKeJ68tiansQ8t2BDQWpj8
SiqQ8B5s2auNivdtttuI5P8ZJ/GsAE5YJcvehf0IHLN94BftZGDVMADAx+ldTIvq
smNRrDfp9d5lehfdHUX/NTddw9LBYG+43W4mTeXf+5jSoGmT49vJx+QeAPgaHDZ9
5H6r3eRHs7noDjfYGK8PhdnPJKHO/aOQE1ZO3tVNNAf29M1zkBdJOjvOau2eFwK0
5VA96jY93IlDZ1mChq9b2hNF1GJN3qf38xIYuJxTR9qIuFmYT41MpAIdneXkj3A8
8uYdERyWMAFUm0sOObnhCbxy4MUJUjsgZbfqO/0YO3nFlbhh+SWN6du/nycf2J0j
09/aqvDXxBujoHir6zbOt0qIbKi+GP/24yUGDDHHted/xN7xkuRrBLhype0i8ZkC
9HSx7rpME5t/Ejms9Vxhz3Am63Lu7JUUeDQei2ap3d9NbwXfBGc4BxBFjxcDHjj3
UIcAasvFWkoya5fCvx/2gSpSivuQ2de7cPyTZKeMdnip0vnSIJIPsqnl+cLBJ+PO
vCSNTNzQrZrlYw==
=cI39
-----END PGP SIGNATURE-----
