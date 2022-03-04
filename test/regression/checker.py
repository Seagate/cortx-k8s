###########################################################
# checker.py
#
# Module to facilitate making specific pass/fail test points
#
# Usage:
# * Create a Checker object.  (If a logger object is not provided
#     one will be created.
# * Use "test_pass" or "test_fail" methods to indicate a pass/fail
# * Use "test" method to log a pass/fail based on the boolean/
#     conditional that is passed in.
# * Use "test_equal" to test if a test value is equal to the
#     expected value.
#
# In all cases, the user must provide a message string that will
# be logged with the result.
#
# At then end of a test program, call the result method to
# print a summary of the results.
# * Return value 1 indicates at least one test failure
# * Return value 0 indicates pass
#
###########################################################

from utils import Logger

class Checker:

    def __init__(self, logger=None):
        """Helper class to process pass/fail results."""
        if not logger:
            logger = Logger()
        self.logger = logger

        self.count = 0
        self.fails = []


    def result(self):
        if self.fails:
            self.logger.logfail()
            self.logger.logfail('F '*20)
            self.logger.logfail(' F'*20)
            self.logger.logfail()
            self.logger.logfail('{0} of {1} tests failed'.format(len(self.fails), self.count).center(40))
            self.logger.logfail()
            for msg in self.fails:
                self.logger.logfail('FAIL  ' + msg)
            self.logger.logfail()

            self.logger.logfail('F '*20)
            self.logger.logfail(' F'*20)
            self.logger.logfail()
            return 1
        else:
            self.logger.log()
            self.logger.logpass('*'*40)
            self.logger.logpass('*' + ' '*38 + '*')
            self.logger.logpass('*' + '{0} of {0} tests passed'.format(self.count).center(38) + '*')
            self.logger.logpass('*' + ' '*38 + '*')
            self.logger.logpass('*'*40)
            self.logger.log()
            return 0

    def test_pass(self, msg):
        self.logger.logpass('PASS  ' + msg)
        self.count += 1

    def test_fail(self, msg):
        self.logger.logfail('FAIL  ' + msg)
        self.count += 1
        self.fails.append(msg)

    def test(self, condition, msg):
        if condition:
            self.test_pass(msg)
        else:
            self.test_fail(msg)

    def test_equal(self, expected, actual, msg):
        if expected == actual:
            self.test_pass(msg)
        else:
            self.test_fail(msg + ('expected=%s, actual=%s'%(expected, actual)))

