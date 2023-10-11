## 2.0.0 (2023-10-11)

- Fixed script to detect changed "synoshare" command output. Script now works for both DSM 6 and 7.

- Changed/updated script "help" documentation. Notes updated & moved to README.md file.

- Changed few things to resolve problems with DSM 7 slightly changing how "accessed" entries for shares are created in the Synology Connection database.

- Changed the default value of the "days" option from 3 to 2.

- Created a new "strict" option.

- Changed the script to check for database query errors and invalid last "accessed" time values for every share. As a precaution, shares with these errors will be unmounted immediately. These errors also affect the new "strict" option.

- Changed the script to retry unmounting a share max. 3 times.

- Changed the script so that if it finds an invalid share name from the "synoshare" command output, or if unmounting a share fails after retries, it logs all of these errors and emails them at the end of the script execution. This way a share related error won't prevent trying to close the rest of the shares.

## 1.0.0 (2020-03-10)

- First release.
