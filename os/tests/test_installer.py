import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('installer', Path(__file__).resolve().parents[1] / 'installer.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class DiskSafety(unittest.TestCase):
    def disk(self, **changes):
        return dict({'type': 'disk', 'ro': False, 'size': 32 * 1024**3,
                     'mountpoints': [None], 'serial': 'HN_TEST', 'children': []}, **changes)

    def test_partition_device_names(self):
        self.assertEqual(installer.partitions('/dev/nvme0n1')[-1], '/dev/nvme0n1p3')
        self.assertEqual(installer.partitions('/dev/mmcblk0')[-1], '/dev/mmcblk0p3')
        self.assertEqual(installer.partitions('/dev/sda')[-1], '/dev/sda3')

    def test_live_usb_and_mounted_nested_mapper_are_rejected(self):
        for mount in ['/run/archiso/bootmnt', '/', '/home']:
            disk = self.disk(children=[{'mountpoints': [None], 'children': [{'mountpoints': [mount]}]}])
            with self.assertRaises(ValueError):
                installer.validate_disk(disk)

    def test_requires_writable_whole_disk_with_space(self):
        for changes in [{'ro': True}, {'type': 'part'}, {'type': 'loop'}, {'size': 1024}]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                installer.validate_disk(self.disk(**changes))

    def test_unattended_serial_must_match(self):
        installer.validate_disk(self.disk(), 'HN_TEST')
        with self.assertRaises(ValueError):
            installer.validate_disk(self.disk(), 'ANOTHER_DISK')

    def test_config_cannot_inject_commands_or_password_lines(self):
        good = dict(username='programmer', hostname='thinkpad', password='test-password', encrypt=True, disk='/dev/sda')
        installer.validate_config(good)
        for change in [dict(username='root'), dict(username='x;reboot'), dict(hostname='bad name'),
                       dict(password='password\nroot:injected'), dict(disk='/dev/sda;reboot'), dict(encrypt='yes')]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                installer.validate_config(dict(good, **change))


if __name__ == '__main__':
    unittest.main()
