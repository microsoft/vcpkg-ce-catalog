#include <stdio.h>
#include <iostream>
using namespace std;

int testfunc(int iParam, float fParam)
{
    int iLoc = 3;
    float fLoc = 3.14159;
    printf("hello from C %d %f\n", iParam, fParam);
    cout << "hello from C++ " << endl;
    return -iParam;
}

int main()
{
    int iLoc = 2;
    float fLoc = 4.4;

    printf("hello from C in %s\n", __FUNCTION__);
    cout << "hello from C++ in " << __FUNCTION__ << endl;
    testfunc(iLoc, fLoc);
    testfunc(iLoc * 2, fLoc * 2.5);

    return 0;
}